//
//  LoginViewModel.swift
//  ExpresScan
//
//  Owns the PKCE registration handshake. Flow:
//
//   1. Generate a 32-byte `codeVerifier` (base64url) and the matching
//      `codeChallenge` = base64url(SHA-256(codeVerifier)).
//   2. Open `ASWebAuthenticationSession` to the registration URL with
//      `codeChallenge` + a label hint as query items. We pass NO
//      `callbackURLScheme` so the callback comes back as a Universal
//      Link to `manage.polaris.express/expresscan/register/callback`,
//      delivered via `SceneDelegate.scene(_:continue:)`.
//   3. The SceneDelegate posts a NotificationCenter notification with
//      the `code` query parameter. We observe it here, stash the code
//      + the matching `codeVerifier` (so RegistrationViewModel can
//      consume them), and emit `deliveredCode` for the SwiftUI view.
//
//  Spec:
//    - `60-security.md` § 1: Universal Links + PKCE (NO custom URL
//      scheme).
//    - `50-ios.md` § "Universal Links + PKCE registration".
//
//  E-app-wire glues this to `RegistrationViewModel` end-to-end. The
//  skeleton here just delivers the code; the registration POST lives
//  in RegistrationViewModel.
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

    private var session: ASWebAuthenticationSession?
    private var notificationObserver: NSObjectProtocol?

    public override init() {
        super.init()
        observeUniversalLink()
    }

    deinit {
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
        }
    }

    // MARK: - Public API

    /// Kicks off the PKCE handshake. Idempotent — calling it twice
    /// while the session is up does nothing.
    public func start(deviceLabel: String = UIDevice.current.name) {
        guard !isPresenting else { return }
        error = nil
        deliveredCode = nil

        let verifier = Self.generateCodeVerifier()
        let challenge = Self.computeChallenge(verifier: verifier)
        self.lastVerifier = verifier
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

        // `callbackURLScheme: nil` means the callback is delivered via
        // Universal Link (SceneDelegate.scene(_:continue:)), not a
        // custom URL scheme. Per `60-security.md` § 1 — REQUIRED.
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: nil
        ) { [weak self] _, error in
            // We expect this completion handler to fire with
            // (nil, .canceledLogin) on cancel; on a successful UL
            // callback, iOS delivers via the Scene path BEFORE this
            // closure is invoked, so we may also see (nil, nil).
            Task { @MainActor in
                self?.handleSessionCompletion(error: error)
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

    private func handleSessionCompletion(error: Error?) {
        // Always release the session reference.
        session = nil
        isPresenting = false

        guard let error else { return }

        // ASWebAuthenticationSession returns a specialised error
        // domain; map to our small enum.
        if let authErr = error as? ASWebAuthenticationSessionError {
            switch authErr.code {
            case .canceledLogin:
                self.error = .canceled
            case .presentationContextNotProvided,
                 .presentationContextInvalid:
                self.error = .presentation
            @unknown default:
                self.error = .unknown
            }
        } else {
            self.error = .unknown
        }
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
        // don't own the UIWindow ourselves.
        // This callback is invoked on the main thread by AuthServices.
        return MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first(where: { $0.activationState == .foregroundActive })
            return scene?.keyWindow ?? ASPresentationAnchor()
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
