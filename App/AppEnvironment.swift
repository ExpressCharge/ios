//
//  AppEnvironment.swift
//  ExpresScan
//
//  Process-wide injection point for the long-lived service singletons
//  (`APIClient`, `AuthStore`, theme, baseURL). Threaded into the SwiftUI
//  hierarchy via `.environment(\.app, AppEnvironment.shared)` and made
//  available to UIKit shims (AppDelegate / SceneDelegate) via the
//  `AppEnvironment.shared` static.
//
//  Wire-in (E-app-wire) will add `ScanCoordinator`, `PushService`,
//  `NFCService`, `DeviceStateCoordinator`, etc. The skeleton wires only
//  the pieces the auth + onboarding flow needs.
//
//  Spec: `50-ios.md` § "Project structure" — `AppEnvironment.swift`.
//

import AuthCore
import DeviceLogging
import Foundation
import Networking
import SwiftUI
import os

/// App-wide loggers, scoped by category. Use these instead of `print`
/// for any state transition or failure path. The `subsystem` matches
/// our App ID so OSLogStore queries (and the QA Console.app filter)
/// pick up everything in one place.
public let scanLog = Logger(subsystem: "com.example.expresscharge.ios", category: "scan")
public let netLog = Logger(subsystem: "com.example.expresscharge.ios", category: "network")
public let nfcLog = Logger(subsystem: "com.example.expresscharge.ios", category: "nfc")
public let authLog = Logger(subsystem: "com.example.expresscharge.ios", category: "auth")

/// Per-build constants that can't be discovered at runtime. Single
/// source of truth for the API base URL and APNs environment. The
/// xcodegen `project.yml` flips `APNS_SANDBOX` / `APNS_PRODUCTION`
/// active compilation conditions per-config.
public enum BuildConfig {
    /// HTTPS base URL of the expresscharge backend. The Fresh monolith
    /// serves both the admin web UI (`/admin/*`, `/app/*`) and
    /// the iOS-facing API (`/api/devices/*`) from the SAME host —
    /// `manage.example.com`. There is no separate `api.` subdomain.
    /// (See `expresscharge/.env.example` `ADMIN_BASE_URL` line and the
    /// register-route test fixture which posts to
    /// `https://manage.example.com/api/devices/register`.)
    public static var apiBaseURL: URL {
        URL(string: "https://manage.example.com")!
    }

    /// The APNs environment a freshly-minted push token should be
    /// registered under. Mirrors the entitlement's `aps-environment`.
    public static var apnsEnvironment: String {
        #if APNS_PRODUCTION
        return "production"
        #else
        return "sandbox"
        #endif
    }

    /// Universal Link host for the registration callback. Used when
    /// matching incoming `NSUserActivity` URLs in the SceneDelegate
    /// (the belt-and-braces path for stale callbacks tapped outside
    /// an active auth session).
    public static let universalLinkHost = "manage.example.com"

    /// Path prefix on the universal-link host that we react to.
    public static let registrationCallbackPath = "/app/register/callback"

    /// Customer-facing host that carries charger sticker links —
    /// `https://example.com/c/<id>`. Distinct from
    /// `universalLinkHost` (admin, used for OAuth registration only)
    /// because the customer flow lives on the customer surface; admins
    /// don't scan stickers. Migration 0043 (ExpresSync).
    public static let chargerLinkHost = "example.com"

    /// Path prefix for charger sticker links — `/c/<chargeBoxId>`.
    /// Migration 0043 (ExpresSync). Tapping a sticker (NFC NDEF URL or
    /// QR) on an unmanaged charger lands here; the universal link
    /// handler extracts the trailing id and routes to ChargersTabView.
    public static let chargerDeepLinkPath = "/c/"

    /// Custom URL scheme that `ASWebAuthenticationSession` is registered
    /// to intercept. The web admin's POST handler 302s the in-session
    /// browser to `expchg://register/callback?code=…`; iOS sees the
    /// scheme match the session's `callbackURLScheme`, dismisses the
    /// auth view, and delivers the URL to the completion handler. The
    /// same scheme also carries `expchg://c/<id>` charger deep links
    /// (Migration 0043) — the `c` host mirrors the `/c/` path on the
    /// universal-link form so both shapes read the same on stickers
    /// and docs.
    public static let callbackURLScheme = "expchg"

    /// Host segment for charger deep links delivered via the custom
    /// scheme: `expchg://c/<chargeBoxId>`. Mirrors `chargerDeepLinkPath`
    /// on the universal-link side.
    public static let chargerDeepLinkSchemeHost = "c"

    /// Web-side login starting point for the PKCE-protected
    /// registration flow. Always lives on the production host because
    /// the web admin UI is single-environment.
    public static let registrationStartURL = URL(
        string: "https://manage.example.com/app/register")!

    /// User-facing app version, sourced from the bundle. Includes the
    /// build number in parens — used in admin-only Settings + the
    /// Diagnostics sheet.
    public static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    /// Marketing version only (no build number). Shown in the
    /// customer-mode Settings page where the build counter is internal
    /// noise.
    public static var shortVersion: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}

/// Long-lived application-wide services. Treat as a single,
/// shared owner — read-only after launch. Internally the contained
/// services (AuthStore actor, APIClient actor) handle their own
/// concurrency.
public final class AppEnvironment: @unchecked Sendable {

    /// Lazily-initialised process singleton. SwiftUI views read this
    /// via `@Environment(\.app)`; UIKit shims read it directly.
    public static let shared = AppEnvironment()

    public let authStore: AuthStore
    public let api: APIClient
    /// Process-wide reachability monitor. Started by `RootView` once
    /// the SwiftUI hierarchy is up.
    public let reachability: ReachabilityMonitor

    /// Track I5 — coarse location for the Chargers tab. Started/
    /// stopped by `ChargersTabView` on focus change. Lives at the
    /// process level so the same fix backs distance + primary-card
    /// rendering across navigations.
    @MainActor public lazy var locationService: LocationService = {
        LocationService()
    }()

    /// Set by `RootCoordinator.bootstrap(...)` once the SwiftUI
    /// hierarchy is up. The `AppDelegate` then forwards APNs payloads
    /// + token uploads through this reference.
    @MainActor public weak var pushService: PushService?

    /// Phase 3a — handles installed by `LoggingBootstrap.bootstrap(...)`
    /// once `RootCoordinator.bootstrap(...)` has the device id from the
    /// keychain. `nil` until then; the swift-log façade still emits to
    /// Console.app via `OSLogHandler` immediately on first use, but the
    /// durable JSONL ring buffer only starts capturing once this is set.
    @MainActor public private(set) var loggingHandles: LoggingBootstrap.Handles?

    /// Phase 3a — drain handed to `DeviceStateCoordinator` so each sync
    /// flushes up to 100 OTel log records server-side. `nil` until
    /// logging bootstraps.
    @MainActor public private(set) var logDrain: LogDrain?

    /// Install logging handles after the async bootstrap has resolved.
    /// Idempotent — second-call behaviour replaces the previous drain
    /// (the underlying store is the same actor instance).
    @MainActor
    public func setLoggingHandles(_ handles: LoggingBootstrap.Handles) {
        self.loggingHandles = handles
        self.logDrain = LogDrain(store: handles.store)
    }

    /// Test-only initialiser. Allows unit tests to inject a stubbed
    /// `APIClient` (and a fresh `AuthStore`) without touching the
    /// process-wide `.shared` singleton.
    internal init(api: APIClient, authStore: AuthStore) {
        self.api = api
        self.authStore = authStore
        self.reachability = ReachabilityMonitor(apiBaseURL: BuildConfig.apiBaseURL)
    }

    private init() {
        let auth = AuthStore()
        self.authStore = auth
        let monitor = ReachabilityMonitor(apiBaseURL: BuildConfig.apiBaseURL)
        self.reachability = monitor
        // The `tokenSource` closure runs on every request — pulling
        // straight from the keychain means token rotation after a
        // re-register Just Works without re-creating the client.
        // `failureReporter` lets the reachability monitor react to
        // real request failures without waiting for its periodic poll.
        self.api = APIClient(
            baseURL: BuildConfig.apiBaseURL,
            tokenSource: { [auth] in
                (try? await auth.loadDeviceToken()) ?? nil
            },
            userAgent: "ExpresScan/\(BuildConfig.appVersion) (iOS)",
            failureReporter: { [weak monitor] in
                monitor?.reportTransportFailure()
            }
        )
    }
}

// MARK: - SwiftUI environment plumbing

private struct AppEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppEnvironment = AppEnvironment.shared
}

extension EnvironmentValues {
    /// Access via `@Environment(\.app) private var app`.
    public var app: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
