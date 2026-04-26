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
//  `NFCService`, `HeartbeatService`, etc. The skeleton wires only the
//  pieces the auth + onboarding flow needs.
//
//  Spec: `50-ios.md` § "Project structure" — `AppEnvironment.swift`.
//

import Foundation
import SwiftUI

import AuthCore
import Networking

/// Per-build constants that can't be discovered at runtime. Single
/// source of truth for the API base URL and APNs environment. The
/// xcodegen `project.yml` flips `APNS_SANDBOX` / `APNS_PRODUCTION`
/// active compilation conditions per-config.
public enum BuildConfig {
    /// HTTPS base URL of the expresync backend. Compile-time switch
    /// based on the active scheme's API_BASE_URL build setting.
    public static var apiBaseURL: URL {
        #if APNS_PRODUCTION
        return URL(string: "https://api.example.com")!
        #else
        return URL(string: "https://dev.api.example.com")!
        #endif
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
    /// matching incoming `NSUserActivity` URLs in the SceneDelegate.
    public static let universalLinkHost = "manage.example.com"

    /// Path prefix on the universal-link host that we react to.
    public static let registrationCallbackPath = "/expresscan/register/callback"

    /// Web-side login starting point for the PKCE-protected
    /// registration flow. Always lives on the production host because
    /// the web admin UI is single-environment.
    public static let registrationStartURL = URL(string: "https://manage.example.com/expresscan/register")!

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

    private init() {
        let auth = AuthStore()
        self.authStore = auth
        // The `tokenSource` closure runs on every request — pulling
        // straight from the keychain means token rotation after a
        // re-register Just Works without re-creating the client.
        self.api = APIClient(
            baseURL: BuildConfig.apiBaseURL,
            tokenSource: { [auth] in
                (try? await auth.loadDeviceToken()) ?? nil
            },
            userAgent: "ExpresScan/\(BuildConfig.appVersion) (iOS)"
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
