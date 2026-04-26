//
//  SceneDelegate.swift
//  ExpresScan
//
//  UIWindowSceneDelegate adopted so we can hook
//  `scene(_:continue:)` for Universal Link delivery — the registration
//  callback comes back via `https://manage.example.com/expresscan/register/callback`
//  per `60-security.md` § 1.
//
//  The window itself is owned by SwiftUI's `WindowGroup` — we don't
//  build a `UIWindow` here; iOS hands one back via the SceneDelegate
//  whose `window` property points at the SwiftUI-managed root. We just
//  observe lifecycle + Universal Link continuation.
//

import UIKit

@MainActor
final class SceneDelegate: NSObject, UIWindowSceneDelegate {

    var window: UIWindow?

    // MARK: - Universal Link entry-point

    /// First-launch case: the app was cold-started by tapping a
    /// Universal Link.
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        // SwiftUI builds the actual `UIWindow` for us — `self.window`
        // gets populated automatically during the scene lifecycle.
        // We just inspect the launch userActivities.
        for activity in connectionOptions.userActivities {
            handle(userActivity: activity)
        }
    }

    /// Hot-launch case: app was already running, user tapped a UL.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        handle(userActivity: userActivity)
    }

    // MARK: - Foreground / background lifecycle

    /// Cancel the heartbeat task when we go inactive — saves battery
    /// + keeps SSE TCP connection draining naturally on the next
    /// background tick.
    func sceneDidEnterBackground(_ scene: UIScene) {
        AppEnvironment.shared.pushService?.coordinator?.handleEnterBackground()
    }

    /// Re-arm the heartbeat + drain any pending offline scan results.
    func sceneWillEnterForeground(_ scene: UIScene) {
        AppEnvironment.shared.pushService?.coordinator?.handleEnterForeground()
    }

    // MARK: - Routing

    /// Extracts the `code` query item from a registration-callback UL.
    /// Posts a NotificationCenter notification so the SwiftUI view-model
    /// can pick it up without taking a UIKit dependency.
    ///
    /// E-app-wire replaces the NotificationCenter post with a direct
    /// call into `RegistrationCoordinator.handleCallback(code:)`.
    private func handle(userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return
        }

        // Match host + path prefix. We don't `==` the path because the
        // backend may grow `…/callback/` trailing slashes, query
        // ordering, etc.
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
