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

import Foundation
import SwiftUI
import os

import AuthCore
import Networking

/// App-wide loggers, scoped by category. Use these instead of `print`
/// for any state transition or failure path. The `subsystem` matches
/// our App ID so OSLogStore queries (and the QA Console.app filter)
/// pick up everything in one place.
public let scanLog = Logger(subsystem: "gg.vlad.expresscan", category: "scan")
public let netLog = Logger(subsystem: "gg.vlad.expresscan", category: "network")
public let nfcLog = Logger(subsystem: "gg.vlad.expresscan", category: "nfc")
public let authLog = Logger(subsystem: "gg.vlad.expresscan", category: "auth")

/// Per-build constants that can't be discovered at runtime. Single
/// source of truth for the API base URL and APNs environment. The
/// xcodegen `project.yml` flips `APNS_SANDBOX` / `APNS_PRODUCTION`
/// active compilation conditions per-config.
public enum BuildConfig {
    /// HTTPS base URL of the expressync backend. The Fresh monolith
    /// serves both the admin web UI (`/admin/*`, `/expresscan/*`) and
    /// the iOS-facing API (`/api/devices/*`) from the SAME host —
    /// `manage.polaris.express`. There is no separate `api.` subdomain.
    /// (See `expressync/.env.example` `ADMIN_BASE_URL` line and the
    /// register-route test fixture which posts to
    /// `https://manage.polaris.express/api/devices/register`.)
    public static var apiBaseURL: URL {
        URL(string: "https://manage.polaris.express")!
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
    public static let universalLinkHost = "manage.polaris.express"

    /// Path prefix on the universal-link host that we react to.
    public static let registrationCallbackPath = "/expresscan/register/callback"

    /// Custom URL scheme that `ASWebAuthenticationSession` is registered
    /// to intercept. The web admin's POST handler 302s the in-session
    /// browser to `expresscan://register/callback?code=…`; iOS sees the
    /// scheme match the session's `callbackURLScheme`, dismisses the
    /// auth view, and delivers the URL to the completion handler. Not
    /// registered in `Info.plist` `CFBundleURLTypes` — Apple does not
    /// require that for the auth-session path, and skipping it avoids
    /// dispatching stray `expresscan://` URLs from elsewhere.
    public static let callbackURLScheme = "expresscan"

    /// Web-side login starting point for the PKCE-protected
    /// registration flow. Always lives on the production host because
    /// the web admin UI is single-environment.
    public static let registrationStartURL = URL(string: "https://manage.polaris.express/expresscan/register")!

    /// User-facing app version, sourced from the bundle.
    public static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
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

    /// Set by `RootCoordinator.bootstrap(...)` once the SwiftUI
    /// hierarchy is up. The `AppDelegate` then forwards APNs payloads
    /// + token uploads through this reference.
    @MainActor public weak var pushService: PushService?

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
