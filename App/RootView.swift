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

import AuthCore
import Capabilities
import DeviceLogging
import DeviceSync
import Models
import SwiftUI

/// Environment key carrying the live `isCustomerAccount` flag derived
/// from `RootCoordinator.deviceState?.state?.ownerUser.role`. Defaults
/// to `false` so admin chrome never accidentally hides at cold launch.
private struct IsCustomerAccountEnvironmentKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    public var isCustomerAccount: Bool {
        get { self[IsCustomerAccountEnvironmentKey.self] }
        set { self[IsCustomerAccountEnvironmentKey.self] = newValue }
    }
}

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
    /// Customer sign-in in flight (QR / magic-email / future NFC tap)
    /// — drives `CustomerSignInProgressView` through a phased status
    /// sequence between `.welcome` and `.ready`. Plan B2 / task #8.
    case customerSigningIn(method: CustomerSignInMethod, phase: CustomerSignInPhase)
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
    /// Live for the duration of a signed-in session. Drives the 60s
    /// device-state sync loop that replaced the empty heartbeat, and
    /// owns the live capability set the SwiftUI shell renders against.
    public private(set) var deviceState: DeviceStateCoordinator?
    /// Live for the duration of the app process (after `bootstrap`).
    @ObservationIgnored
    public private(set) var push: PushService?

    public init() {}

    // MARK: - Capability / role proxies for SwiftUI descendants
    //
    // These are computed proxies over the live `DeviceStateCoordinator`,
    // so the @Observable change-tracking on `deviceState` propagates to
    // descendants reading these properties.

    /// SwiftUI-observable feature-flag reader. Returns a fresh empty
    /// reader when the device-state coordinator hasn't been constructed
    /// yet (cold launch / unauthenticated states) — callers always get
    /// the registry default for any key.
    public var featureFlagReader: FeatureFlagReader {
        deviceState?.featureFlagReader ?? Self.emptyFlagReader
    }

    /// SwiftUI-observable settings reader. Same fallback as above.
    public var settingsReader: SettingsReader {
        deviceState?.settingsReader ?? Self.emptySettingsReader
    }

    /// `true` when the signed-in user's role is `.customer`. Defaults to
    /// `false` whenever the role is unknown (no envelope yet, signed
    /// out, etc.) so admin chrome never accidentally hides at cold
    /// launch.
    public var isCustomerAccount: Bool {
        deviceState?.state?.ownerUser.role == .customer
    }

    @ObservationIgnored
    private static let emptyFlagReader = FeatureFlagReader()
    @ObservationIgnored
    private static let emptySettingsReader: SettingsReader = {
        // Process-wide fallback store rooted in tmp; only used for the
        // unauthenticated shell so writes here are inert.
        let store =
            (try? SettingsStore(directoryURL: FileManager.default.temporaryDirectory))
            ?? (try! SettingsStore(directoryURL: FileManager.default.temporaryDirectory))
        return SettingsReader(store: store)
    }()

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

        // Phase 3a — install the swift-log multiplex (Console.app +
        // durable JSONL ring buffer). Done before
        // `ensureDeviceStateCoordinator(...)` so the coordinator picks
        // up the drain on first construction.
        if environment.loggingHandles == nil {
            let deviceId: String = (try? await environment.authStore.loadDeviceID()) ?? ""
            do {
                let handles = try await DeviceLogging.LoggingBootstrap.bootstrap(
                    deviceId: deviceId,
                    serviceVersion: BuildConfig.shortVersion,
                    osName: UIDevice.current.systemName,
                    osVersion: UIDevice.current.systemVersion
                )
                environment.setLoggingHandles(handles)
            } catch {
                // Logging bootstrap is best-effort. The
                // `OSLogHandler` half of the multiplex still works
                // because swift-log fell back to its default
                // `StreamLogHandler`; we just lose durable capture.
                scanLog.error(
                    "LoggingBootstrap failed: \(String(describing: error), privacy: .public)"
                )
            }
        }

        let hasCreds = await environment.authStore.hasValidCredentials()
        if hasCreds {
            ensureScanCoordinator(environment: environment)
            self.route = .ready
            scan?.startConnecting()
            deviceState?.bootstrap()
            // Cold-launch APNs refresh: re-deliver the token via the
            // AppDelegate callback (so we PUT /push-token even when
            // iOS dedupes a same-token re-registration on a later
            // launch) and drain any token stashed pre-deviceId. This
            // is the safety net for devices that registered with an
            // empty `pushToken` because the 5 s wait at submit time
            // expired before iOS delivered.
            push?.refreshIfAuthenticated()
        } else {
            self.route = .welcome
        }
    }

    /// Lazy-create or return the existing `ScanCoordinator`. Called on
    /// every `.ready` transition (registration, foreground, sign-in).
    /// Also lazy-creates the `DeviceStateCoordinator` alongside it; the
    /// two coordinators have the same signed-in lifetime.
    @discardableResult
    public func ensureScanCoordinator(environment: AppEnvironment) -> ScanCoordinator {
        if let existing = scan {
            ensureDeviceStateCoordinator(environment: environment)
            return existing
        }
        ensureDeviceStateCoordinator(environment: environment)
        let coordinator = ScanCoordinator(
            environment: environment,
            deviceState: deviceState
        )
        coordinator.attach(router: self)
        scan = coordinator
        // Hook the push service to the coordinator now that we have one.
        push?.coordinator = coordinator
        return coordinator
    }

    /// Lazy-create the device-state coordinator. Constructed up-front so
    /// the cold-launch capability cache is consulted before the SwiftUI
    /// shell renders.
    @discardableResult
    public func ensureDeviceStateCoordinator(
        environment: AppEnvironment
    ) -> DeviceStateCoordinator {
        if let existing = deviceState { return existing }
        // The settings store is process-wide; constructed lazily here.
        let store: SettingsStore
        do {
            store = try SettingsStore()
        } catch {
            // Persistence failure is rare (sandbox dir not writable);
            // fall back to an in-memory store rooted in a temp dir.
            store =
                (try? SettingsStore(directoryURL: FileManager.default.temporaryDirectory))
                ?? (try! SettingsStore(directoryURL: FileManager.default.temporaryDirectory))
        }
        let coordinator = DeviceStateCoordinator(
            api: environment.api,
            settingsStore: store,
            logDrain: environment.logDrain
        )
        coordinator.attach(router: self)
        deviceState = coordinator
        return coordinator
    }

    /// Tear down the `ScanCoordinator` on sign-out.
    private func teardownScanCoordinator() {
        scan?.stopConnecting()
        scan = nil
        deviceState?.stop()
        deviceState = nil
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
            deviceState?.bootstrap()
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
            case .customerSigningIn(_, let phase):
                CustomerSignInProgressView(
                    phase: phase,
                    onTryAgain: { coordinator.route = .welcome }
                )
            case .ready:
                // Capabilities sourced from the live
                // `DeviceStateCoordinator`. Until `bootstrap()` resolves
                // the first network call, the coordinator surfaces the
                // cached capability set (or the registration default
                // `{.scanner, .user}` if no cache exists). SSE-driven
                // capability changes refresh `coordinator.deviceState`,
                // which is `@Observable` — the View re-renders
                // automatically.
                readyShell
            }
        }
        // Plumb the SwiftUI-observable readers + customer-role flag into
        // the environment so descendants (Settings, Diagnostics, etc.)
        // can read them without prop-drilling. The proxies on
        // RootCoordinator fall back to inert empty readers when the
        // device-state coordinator isn't constructed yet.
        .environment(coordinator.featureFlagReader)
        .environment(coordinator.settingsReader)
        .environment(\.isCustomerAccount, coordinator.isCustomerAccount)
        .background(Theme.color(.background))
        .preferredColorScheme(nil)  // honor system setting
        .fullScreenCover(isPresented: connectivityOverlayBinding) {
            OfflineOverlay(
                state: app.reachability.state,
                nextProbeAt: app.reachability.nextProbeAt,
                currentBackoffSeconds: app.reachability.currentBackoffSeconds
            )
            .interactiveDismissDisabled(true)
        }
        .task {
            app.reachability.start()
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
        .onReceive(
            NotificationCenter.default.publisher(
                for: AppNotifications.userQrSignInRequested)
        ) { note in
            guard let publicId = note.userInfo?["publicId"] as? String else {
                return
            }
            // Only run the QR sign-in when we're in the unauthenticated
            // shell — once we're past .ready the user is already signed
            // in and the URL is a no-op.
            switch coordinator.route {
            case .welcome, .loggingIn, .launching, .customerSigningIn:
                Task { await runQrSignIn(publicId: publicId) }
            default:
                return
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: AppNotifications.magicEmailSignInRequested)
        ) { note in
            guard let token = note.userInfo?["token"] as? String else {
                return
            }
            switch coordinator.route {
            case .welcome, .loggingIn, .launching, .customerSigningIn:
                Task { await runMagicEmailSignIn(token: token) }
            default:
                return
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                coordinator.scan?.handleEnterBackground()
                coordinator.deviceState?.handleEnterBackground()
            case .active:
                coordinator.scan?.handleEnterForeground()
                coordinator.deviceState?.handleEnterForeground()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    /// Bindings into the reachability monitor — `true` whenever the
    /// monitor is reporting anything other than `.online`. Suppress
    /// during cold launch so we don't fight the auth gate.
    private var connectivityOverlayBinding: Binding<Bool> {
        Binding(
            get: {
                guard coordinator.route != .launching else { return false }
                return app.reachability.state != .online
            },
            set: { _ in /* dismissal driven by the monitor itself */ }
        )
    }

    /// Mounts `MainTabContainer` with a `.id(...)` keyed off the live
    /// capability set so SSE-driven capability changes re-create the
    /// shell rather than diff a stale `@State`-cached view-model.
    @ViewBuilder
    private var readyShell: some View {
        let caps =
            coordinator.deviceState?.capabilities
            ?? DeviceStateCoordinator.defaultCapabilities
        MainTabContainer(capabilities: caps)
            .environment(coordinator)
            .id(caps.map(\.rawValue).sorted().joined(separator: ","))
    }

    private func handleUniversalLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return
        }

        // 1. Charger sticker deep link — Migration 0043.
        // Universal: `https://example.com/c/<id>` (customer surface)
        // Custom:    `expchg://c/<id>`
        if let chargerId = parseChargerDeepLink(components) {
            NotificationCenter.default.post(
                name: AppNotifications.chargerDeepLinkRequested,
                object: nil,
                userInfo: ["chargerId": chargerId]
            )
            return
        }

        // 2a. Magic-email customer sign-in — Plan B2 / task #8.
        // Universal: `https://example.com/m/<token>`. The token is
        // verified by the server; the iOS side only enforces a length
        // + URL-safe alphabet so a crafted /m/ URL doesn't cause a
        // wasted POST.
        if let token = MagicEmailDeepLinkHandler.parse(components) {
            NotificationCenter.default.post(
                name: AppNotifications.magicEmailSignInRequested,
                object: nil,
                userInfo: ["token": token]
            )
            return
        }

        // 2. User QR sign-in deep link — Track I7.
        // Universal: `https://example.com/u/<publicId>` printed on
        // the customer's charge card. Camera scan → AASA matches /u/* →
        // iOS hands the URL to ExpresScan, which posts to
        // `/api/auth/qr-sign-in` to mint a session + register the
        // device + auto-bind a per-device OCPP tag.
        if let publicId = parseUserSignInDeepLink(components) {
            NotificationCenter.default.post(
                name: AppNotifications.userQrSignInRequested,
                object: nil,
                userInfo: ["publicId": publicId]
            )
            return
        }

        // 3. Registration PKCE callback (the original flow).
        guard
            components.host == BuildConfig.universalLinkHost,
            components.path == BuildConfig.registrationCallbackPath
        else {
            return
        }
        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
            !code.isEmpty
        else {
            return
        }
        NotificationCenter.default.post(
            name: AppNotifications.universalLinkRegistrationCallback,
            object: nil,
            userInfo: ["code": code]
        )
    }

    /// Run the iOS-only QR sign-in pipeline: POST the publicId, persist
    /// the returned credentials, then ask the coordinator to re-bootstrap
    /// so the AuthStore lookup picks up the new tokens and advances the
    /// route to `.ready`.
    private func runQrSignIn(publicId: String) async {
        let method: CustomerSignInMethod = .qrCode(publicId: publicId)
        coordinator.route = .customerSigningIn(method: method, phase: .confirming)

        let vm = QrSignInViewModel(api: app.api, authStore: app.authStore)
        let ok = await vm.signIn(publicId: publicId)
        if ok {
            coordinator.route = .customerSigningIn(method: method, phase: .finalizing)
            coordinator.route = .customerSigningIn(method: method, phase: .success)
            try? await Task.sleep(nanoseconds: 600_000_000)
            await coordinator.bootstrap(environment: app)
            return
        }
        // Failure stays on the progress view; the retry CTA returns
        // the user to Welcome via `onTryAgain`.
        let message: String
        if case .error(let text, _) = vm.loadState {
            message = text
        } else {
            message = "Couldn't sign in. Try scanning again."
        }
        coordinator.route = .customerSigningIn(
            method: method,
            phase: .failure(message: message)
        )
    }

    /// Counterpart to `runQrSignIn` for the magic-email flow.
    private func runMagicEmailSignIn(token: String) async {
        let method: CustomerSignInMethod = .magicEmail(token: token)
        coordinator.route = .customerSigningIn(method: method, phase: .confirming)

        let vm = MagicEmailSignInViewModel(api: app.api, authStore: app.authStore)
        let ok = await vm.signIn(token: token)
        if ok {
            coordinator.route = .customerSigningIn(method: method, phase: .finalizing)
            coordinator.route = .customerSigningIn(method: method, phase: .success)
            try? await Task.sleep(nanoseconds: 600_000_000)
            await coordinator.bootstrap(environment: app)
            return
        }
        let message: String
        if case .failure(let text) = vm.phase {
            message = text
        } else {
            message = "Couldn't sign in. Open the link from your email again."
        }
        coordinator.route = .customerSigningIn(
            method: method,
            phase: .failure(message: message)
        )
    }

    /// Returns the trailing publicId from a user-card sticker URL.
    /// Format must be exactly `https://example.com/u/XXXXXXXX` —
    /// 8 chars from the public-ID alphabet (defended at the server
    /// too, but rejecting bad inputs locally avoids a wasted POST).
    private func parseUserSignInDeepLink(
        _ components: URLComponents
    ) -> String? {
        guard
            (components.scheme ?? "").lowercased() == "https",
            components.host == BuildConfig.chargerLinkHost
        else { return nil }
        let prefix = "/u/"
        guard components.path.hasPrefix(prefix) else { return nil }
        let id = String(components.path.dropFirst(prefix.count))
        return validatedPublicId(id)
    }

    /// Validate that `raw` matches the public-ID alphabet
    /// (`23456789ABCDEFGHJKMNPQRSTVWXYZ`) and is exactly 8 chars long.
    /// The alphabet is hard-coded rather than imported from a shared
    /// module so the parser stays self-contained at the deep-link
    /// boundary.
    private func validatedPublicId(_ raw: String) -> String? {
        guard raw.count == 8 else { return nil }
        let alphabet: Set<Character> = Set(
            "23456789ABCDEFGHJKMNPQRSTVWXYZ")
        return raw.allSatisfy { alphabet.contains($0) } ? raw : nil
    }

    /// Returns the trailing chargeBoxId from a charger sticker URL, in
    /// either form. Defensive: rejects empty / multi-segment ids so a
    /// crafted `/c/foo/bar` doesn't sneak through as `chargerId="foo/bar"`.
    private func parseChargerDeepLink(_ components: URLComponents) -> String? {
        let scheme = (components.scheme ?? "").lowercased()

        // Universal link form: https://example.com/c/<id>
        // Customer host — distinct from `universalLinkHost`, which only
        // carries the admin OAuth callback (`/app/register/callback`).
        if scheme == "https",
            components.host == BuildConfig.chargerLinkHost,
            components.path.hasPrefix(BuildConfig.chargerDeepLinkPath)
        {
            let id = String(
                components.path.dropFirst(BuildConfig.chargerDeepLinkPath.count))
            return validatedChargerId(id)
        }

        // Custom-scheme form: expchg://c/<id>
        if scheme == BuildConfig.callbackURLScheme,
            components.host == BuildConfig.chargerDeepLinkSchemeHost
        {
            let trimmed = components.path.trimmingCharacters(in: ["/"])
            return validatedChargerId(trimmed)
        }

        return nil
    }

    private func validatedChargerId(_ raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        // No path traversal — the chargeBoxId itself is single-segment.
        guard !raw.contains("/") else { return nil }
        return raw
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
