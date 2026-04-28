//
//  RootView.swift
//  ExpresScan
//
//  Auth-gate. On launch, peek at the Keychain (cheap — no biometric
//  prompt because we look up `deviceToken`, not `deviceSecret`) to
//  decide which top-level surface to show.
//
//  Spec: `50-ios.md` § "Project structure" + § "Welcome / login flow".
//
//  Transitions live in `RootCoordinator` (an `@Observable` model). The
//  view itself is a thin switch on the coordinator's enum — every leaf
//  is its own `Feature*View`.
//

import SwiftUI

import AuthCore
import Models

/// Top-level routing state. Order matches the user's first-launch path
/// for readability.
public enum RootRoute: Equatable {
    /// We have valid credentials in the Keychain → show the home
    /// screen. The live `ScanCoordinator` is owned by `RootCoordinator`
    /// and is shared across this branch's lifetime.
    case ready
    /// Fresh install or post-sign-out → show welcome.
    case welcome
    /// Sign-in tapped → ASWebAuthenticationSession is presenting +
    /// awaiting the Universal Link callback.
    case loggingIn
    /// UL callback fired with a `code` → show the registration form.
    /// `codeVerifier` is the PKCE verifier matching the challenge sent
    /// to the web flow; held in memory only.
    case registering(oneTimeCode: String, codeVerifier: String)
    /// Registration succeeded, ask for notification permission.
    case priming
    /// Loading the keychain on first launch (very brief).
    case launching
}

/// `@Observable`-style app router. Lifted out of `RootView` so child
/// views can grab it via `@Environment` instead of prop-drilling.
///
/// Also owns the long-lived `ScanCoordinator` and `PushService`
/// instances — they're created the first time we transition into
/// `.ready` and reused for the lifetime of the signed-in session.
@MainActor
@Observable
public final class RootCoordinator {

    public var route: RootRoute = .launching

    @ObservationIgnored
    public weak var environment: AppEnvironment?

    /// Live for the duration of a signed-in session. `nil` when the
    /// user is unauthenticated (welcome/login/registering/priming).
    @ObservationIgnored
    public private(set) var scan: ScanCoordinator?
    /// Live for the duration of the app process (after `bootstrap`).
    @ObservationIgnored
    public private(set) var push: PushService?

    public init() {}

    /// Loads credentials and transitions to `.ready` or `.welcome`.
    public func bootstrap(environment: AppEnvironment) async {
        self.environment = environment

        // PushService is constructed eagerly so the AppDelegate can
        // forward APNs token registrations even before sign-in.
        if push == nil {
            let service = PushService(environment: environment)
            push = service
            environment.pushService = service
        }

        let hasCreds = await environment.authStore.hasValidCredentials()
        if hasCreds {
            ensureScanCoordinator(environment: environment)
            self.route = .ready
            scan?.startConnecting()
        } else {
            self.route = .welcome
        }
    }

    /// Lazy-create or return the existing `ScanCoordinator`. Called on
    /// every `.ready` transition (registration, foreground, sign-in).
    @discardableResult
    public func ensureScanCoordinator(environment: AppEnvironment) -> ScanCoordinator {
        if let existing = scan { return existing }
        let coordinator = ScanCoordinator(environment: environment)
        coordinator.attach(router: self)
        scan = coordinator
        // Hook the push service to the coordinator now that we have one.
        push?.coordinator = coordinator
        return coordinator
    }

    /// Tear down the `ScanCoordinator` on sign-out.
    private func teardownScanCoordinator() {
        scan?.stopConnecting()
        scan = nil
        push?.coordinator = nil
    }

    // MARK: - Transitions

    public func startLogin() {
        route = .loggingIn
    }

    public func cancelLogin() {
        route = .welcome
    }

    public func didReceiveOneTimeCode(_ code: String, codeVerifier: String) {
        route = .registering(oneTimeCode: code, codeVerifier: codeVerifier)
    }

    public func didCompleteRegistration() {
        route = .priming
    }

    public func didFinishPriming() {
        if let env = environment {
            ensureScanCoordinator(environment: env)
            scan?.startConnecting()
        }
        route = .ready
    }

    public func didSignOut() {
        teardownScanCoordinator()
        route = .welcome
    }
}

/// Top-level switch view. Each branch is a self-contained Feature view
/// with its own view-model. This keeps the auth-gate trivially testable
/// (set `route` and snapshot the rendered tree).
public struct RootView: View {

    @Environment(\.app) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator = RootCoordinator()

    public init() {}

    public var body: some View {
        ZStack {
            switch coordinator.route {
            case .launching:
                LaunchView()
            case .welcome, .loggingIn:
                // Login uses ASWebAuthenticationSession which presents
                // its own modal — the underlying view stays Welcome. We
                // MUST keep both cases under one switch branch so SwiftUI
                // preserves WelcomeView's structural identity (and its
                // `@State LoginViewModel`) across the `.welcome ↔
                // .loggingIn` transition. Splitting them re-creates the
                // view, deallocating the LoginViewModel that owns the
                // in-flight auth session — the session's completion
                // closure captures `[weak self]`, so the callback fires
                // into a nil `self` and the route is never advanced.
                WelcomeView(showingLoginActivity: coordinator.route == .loggingIn)
                    .environment(coordinator)
            case .registering(let code, let verifier):
                RegistrationView(
                    oneTimeCode: code,
                    codeVerifier: verifier
                )
                    .environment(coordinator)
            case .priming:
                NotificationPrimingView()
                    .environment(coordinator)
            case .ready:
                // TODO(slice-g): replace the hard-coded `[.scanner]`
                // default with a live read from `DeviceStateCoordinator`
                // (which slice G wires in). Until then, scanner-only
                // keeps the existing scan flow working unchanged.
                MainTabContainer(capabilities: [.scanner])
                    .environment(coordinator)
            }
        }
        .background(Theme.color(.background))
        .preferredColorScheme(nil) // honor system setting
        .task {
            await coordinator.bootstrap(environment: app)
        }
        .onOpenURL { url in
            // Universal Link entry-point (custom-scheme path / iOS 18+
            // unified delivery). Most ULs land here.
            handleUniversalLink(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            // Belt-and-braces: some Universal Link delivery paths still
            // use the legacy `NSUserActivity` channel. Same handler.
            if let url = activity.webpageURL {
                handleUniversalLink(url)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                coordinator.scan?.handleEnterBackground()
            case .active:
                coordinator.scan?.handleEnterForeground()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    private func handleUniversalLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == BuildConfig.universalLinkHost,
              components.path == BuildConfig.registrationCallbackPath else {
            return
        }
        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            return
        }
        NotificationCenter.default.post(
            name: AppNotifications.universalLinkRegistrationCallback,
            object: nil,
            userInfo: ["code": code]
        )
    }
}

/// Minimal launch placeholder shown while we read the Keychain. Should
/// be visible for <100ms in practice.
private struct LaunchView: View {
    var body: some View {
        ZStack {
            Theme.color(.background)
                .ignoresSafeArea()
            ProgressView()
                .controlSize(.large)
        }
    }
}
