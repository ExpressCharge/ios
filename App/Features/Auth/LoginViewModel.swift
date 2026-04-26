//
//  LoginViewModel.swift
//  ExpresScan
//
//  Owns the PKCE registration handshake. Flow:
//
//   1. Generate a 32-byte `codeVerifier` (base64url) and the matching
//      `codeChallenge` = base64url(SHA-256(codeVerifier)).
//   2. Open `ASWebAuthenticationSession` to the registration URL with
//      `codeChallenge` + a label hint as query items. The session is
//      configured with `callbackURLScheme: "expresscan"`; the web
//      admin's POST handler 302s the in-session browser to
//      `expresscan://register/callback?code=…`, AuthServices matches
//      the scheme, dismisses the auth UI, and hands us the URL via
//      the completion handler.
//   3. We extract the `code` query parameter from the callback URL,
//      stash it together with the matching `codeVerifier`, and emit
//      `deliveredCode` for the SwiftUI view to consume via
//      `RegistrationViewModel`.
//
//  Why custom scheme and not the iOS 17.4+ `.https(host:path:)`
//  Callback API: the modern API was tried first but failed silently on
//  iOS 26 — `session.start()` returned true, no UI presented, and the
//  completion handler never fired despite a confirmed-correct AASA at
//  the origin and on Apple's CDN. Until that is root-caused, the
//  custom-scheme path is reliable across iOS versions and avoids the
//  AASA-validation hot-path entirely.
//
//  The `observeUniversalLink()` notification observer below remains as
//  a belt-and-braces path for stale HTTPS callback links that arrive
//  via `.onOpenURL` outside an active auth session.
//
//  Spec:
//    - `60-security.md` § 1: PKCE for the registration handshake.
//    - `50-ios.md` § "Universal Links + PKCE registration".
//

import Foundation
import AuthenticationServices
import CryptoKit
import Observation
import UIKit

import Crypto

@MainActor
@Observable
public final class LoginViewModel: NSObject {

    /// `true` while ASWebAuthenticationSession is presenting.
    public private(set) var isPresenting: Bool = false
    /// Most recent error to surface in the UI. Cleared at next `start()`.
    public private(set) var error: LoginError?
    /// Set once the Universal Link callback delivers a `code`. The
    /// caller (WelcomeView / RegistrationView) observes this for
    /// transitions.
    public private(set) var deliveredCode: String?
    /// Verifier matching the most recent challenge. Handed to
    /// `RegistrationViewModel` along with the `code`.
    public private(set) var lastVerifier: String?

    @ObservationIgnored
    private var session: ASWebAuthenticationSession?
    /// `@ObservationIgnored` so the `@Observable` macro doesn't wrap
    /// the storage in observation machinery. iOS 26 + Swift 6.3 support
    /// `isolated deinit`, so we no longer need `nonisolated(unsafe)`
    /// to keep the observer reachable from cleanup.
    @ObservationIgnored
    private var notificationObserver: NSObjectProtocol?

    public override init() {
        super.init()
        observeUniversalLink()
    }

    isolated deinit {
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
        }
    }

    // MARK: - Public API

    /// Kicks off the PKCE handshake. Idempotent — calling it twice
    /// while the session is up does nothing.
    public func start(deviceLabel: String = UIDevice.current.name) {
        guard !isPresenting else {
            authLog.debug("LoginViewModel.start: ignored, session already presenting")
            return
        }
        error = nil
        deliveredCode = nil

        let verifier = Self.generateCodeVerifier()
        let challenge = Self.computeChallenge(verifier: verifier)
        self.lastVerifier = verifier
        authLog.debug("LoginViewModel.start: opening auth session, label.len=\(deviceLabel.count, privacy: .public), verifier.len=\(verifier.count, privacy: .public)")
        // The verifier is read by `WelcomeView.onChange(of:deliveredCode)`
        // and handed to the `RootCoordinator.didReceiveOneTimeCode(_,
        // codeVerifier:)` transition — explicit DI, no globals.

        var components = URLComponents(url: BuildConfig.registrationStartURL, resolvingAgainstBaseURL: false)!
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "codeChallenge", value: challenge))
        items.append(URLQueryItem(name: "codeChallengeMethod", value: "S256"))
        items.append(URLQueryItem(name: "label", value: deviceLabel))
        components.queryItems = items

        guard let url = components.url else {
            error = .urlConstruction
            return
        }

        // The server's POST handler 302s the in-session web view to
        // `expresscan://register/callback?code=…`. AuthServices matches
        // the redirect's scheme against the session's `callbackURLScheme`
        // and — when they match — dismisses the auth UI and delivers
        // the URL to the completion handler. Works reliably across iOS
        // versions and skips the AASA-validation hot-path that the iOS
        // 17.4+ `.https(host:path:)` Callback exposed us to.
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: BuildConfig.callbackURLScheme
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                self?.handleSessionCompletion(callbackURL: callbackURL, error: error)
            }
        }

        session.presentationContextProvider = self
        // From the security audit: leave this `false` so the user's
        // existing web session is reused — better UX, and the auth
        // session's cookie jar is sandboxed regardless.
        session.prefersEphemeralWebBrowserSession = false

        self.session = session
        self.isPresenting = true

        if !session.start() {
            authLog.error("LoginViewModel.start: session.start() returned false")
            self.isPresenting = false
            self.session = nil
            self.error = .sessionStartFailed
        }
    }

    /// Cancels the in-flight web session, if any.
    public func cancel() {
        session?.cancel()
        session = nil
        isPresenting = false
    }

    /// Clear the delivered-code cursor after the consumer (Registration
    /// flow) reads it. Lets the same VM be reused for re-register.
    public func acknowledgeCode() {
        deliveredCode = nil
    }

    // MARK: - Internals

    private func handleSessionCompletion(callbackURL: URL?, error: Error?) {
        // Always release the session reference.
        session = nil
        isPresenting = false

        // Successful HTTPS-callback match — extract the one-time code.
        if let callbackURL, error == nil {
            authLog.debug("LoginViewModel: session completed with callback URL")
            extractCode(from: callbackURL)
            return
        }

        guard let error else { return }

        // ASWebAuthenticationSession returns a specialised error
        // domain; map to our small enum.
        if let authErr = error as? ASWebAuthenticationSessionError {
            switch authErr.code {
            case .canceledLogin:
                authLog.debug("LoginViewModel: session canceled by user")
                self.error = .canceled
            case .presentationContextNotProvided,
                 .presentationContextInvalid:
                authLog.error("LoginViewModel: presentation-context error \(authErr.code.rawValue, privacy: .public)")
                self.error = .presentation
            @unknown default:
                authLog.error("LoginViewModel: unknown ASWebAuthenticationSessionError code \(authErr.code.rawValue, privacy: .public)")
                self.error = .unknown
            }
        } else {
            authLog.error("LoginViewModel: session error \(String(describing: error), privacy: .public)")
            self.error = .unknown
        }
    }

    /// Reads the `?code=…` query item from the callback URL and routes
    /// it through the same channel as the SwiftUI `.onOpenURL` /
    /// `.onContinueUserActivity` handler in `RootView` would. This way
    /// downstream observers (the active `LoginViewModel` instance and
    /// any backup handlers) react identically regardless of how the
    /// URL was delivered.
    private func extractCode(from url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            authLog.error("LoginViewModel.extractCode: failed to parse URL")
            self.error = .unknown
            return
        }

        // Two valid shapes:
        //  - Custom-scheme callback delivered by ASWebAuthenticationSession
        //    after the server's 302 inside the auth view:
        //    `expresscan://register/callback?code=…`.
        //  - HTTPS Universal Link (legacy / belt-and-braces) delivered
        //    via `RootView.onOpenURL` if a stale link is tapped from
        //    elsewhere: `https://manage.example.com/expresscan/
        //    register/callback?code=…`.
        let isCustomScheme = components.scheme == BuildConfig.callbackURLScheme
        let isUniversalLink = components.scheme == "https"
            && components.host == BuildConfig.universalLinkHost
            && components.path == BuildConfig.registrationCallbackPath
        guard isCustomScheme || isUniversalLink else {
            authLog.error("LoginViewModel.extractCode: callback URL did not match expected pattern (scheme=\(components.scheme ?? "nil", privacy: .public))")
            self.error = .unknown
            return
        }

        guard
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
            !code.isEmpty
        else {
            authLog.error("LoginViewModel.extractCode: callback URL missing code query item")
            self.error = .unknown
            return
        }

        authLog.debug("LoginViewModel.extractCode: received one-time code, len=\(code.count, privacy: .public)")
        self.deliveredCode = code
    }

    private func observeUniversalLink() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: AppNotifications.universalLinkRegistrationCallback,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // Capture the code synchronously — it's a primitive String —
            // then hop to MainActor to mutate observed state.
            let code = note.userInfo?["code"] as? String
            Task { @MainActor in
                guard let self else { return }
                if let code, !code.isEmpty {
                    self.deliveredCode = code
                    // The web session is also dismissed by the system
                    // when the Universal Link fires.
                    self.session?.cancel()
                    self.session = nil
                    self.isPresenting = false
                }
            }
        }
    }

    // MARK: - PKCE primitives

    /// Generates a base64url-encoded 32-byte verifier.
    static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return Data(bytes).base64URLEncoded
    }

    /// Computes `base64url(SHA256(verifier))`.
    static func computeChallenge(verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncoded
    }
}

// MARK: - Errors

public enum LoginError: Error, Equatable, Sendable {
    case canceled
    case urlConstruction
    case sessionStartFailed
    case presentation
    case unknown
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension LoginViewModel: ASWebAuthenticationPresentationContextProviding {
    nonisolated public func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        // We MUST return a UIWindow. The first foreground active scene's
        // window is the only viable answer in a SwiftUI app where we
        // don't own the UIWindow ourselves. This callback is invoked
        // on the main thread by AuthServices.
        return MainActor.assumeIsolated {
            // Prefer the foreground scene's keyWindow; fall back to any
            // connected window scene. AuthServices invokes this only
            // while the app is in the foreground, so the third branch
            // (no scenes) is unreachable in practice — we return *some*
            // anchor anyway so the type signature is satisfied.
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
            if let foregroundKey = scenes
                .first(where: { $0.activationState == .foregroundActive })?
                .keyWindow {
                return foregroundKey
            }
            // The first connected scene is the only sensible fallback.
            // If we somehow have zero scenes, the app is in a broken
            // state and AuthServices can't present anyway — we
            // construct a window for whichever scene exists, falling
            // back to the implicit-foreground scene.
            let scene = scenes.first ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
            if let scene {
                return scene.keyWindow ?? UIWindow(windowScene: scene)
            }
            // Truly unreachable in practice; hit only if iOS hands us
            // an `ASWebAuthenticationSession` callback before any
            // window scene has connected.
            preconditionFailure("No connected window scenes for AuthServices anchor")
        }
    }
}

// MARK: - Base64URL encoding (lightweight; no Crypto dependency)

private extension Data {
    /// Base64URL encoding (RFC 4648 §5), no padding.
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
