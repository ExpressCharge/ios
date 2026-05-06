//
//  AppDelegate.swift
//  ExpresScan
//
//  UIKit AppDelegate adopted via `UIApplicationDelegateAdaptor`. Owns:
//    - APNs registration callbacks (token + failure).
//    - `UNUserNotificationCenter` delegate wiring.
//    - Notification category registration (`NFC_SCAN_REQUEST`, no actions
//      per `50-ios.md` § "Push handling").
//
//  E-app-wire fills in the bodies of `userNotificationCenter(_:didReceive:withCompletionHandler:)`
//  and `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`
//  by routing to the `ScanCoordinator`. The skeleton keeps the wiring
//  surface stable so the wire-in is purely additive.
//

import UIKit
import UserNotifications

/// Notifications posted by the AppDelegate so view-models can observe
/// without depending on UIKit. Names live here (single owner) and are
/// listened to from `LoginViewModel`, `RegistrationViewModel`,
/// `ScanCoordinator`, etc.
public enum AppNotifications {
    /// `userInfo["token"] : String` — base64-encoded raw APNs token.
    public static let apnsTokenReceived = Notification.Name("ExpresScan.APNsTokenReceived")
    /// `userInfo["error"] : Error` — APNs registration failed.
    public static let apnsRegistrationFailed = Notification.Name(
        "ExpresScan.APNsRegistrationFailed")
    /// `userInfo["payload"] : [AnyHashable: Any]` — raw APNs payload from
    /// `didReceiveRemoteNotification` (foreground or tap).
    public static let scanRequestPushReceived = Notification.Name(
        "ExpresScan.ScanRequestPushReceived")
    /// `userInfo["code"] : String` — one-time code extracted from a
    /// Universal Link.
    public static let universalLinkRegistrationCallback = Notification.Name(
        "ExpresScan.UniversalLinkRegistrationCallback")
}

/// Identifier of the single notification category we register.
public let scanRequestCategoryIdentifier = "NFC_SCAN_REQUEST"

/// Sendable wrapper for an immutable APNs payload dictionary. The
/// underlying `[AnyHashable: Any]` is not statically Sendable, but
/// the `userInfo` returned by `UNNotificationContent` / the
/// `didReceiveRemoteNotification` callback is owned by us once
/// captured (Foundation copies it), so crossing isolation boundaries
/// with it is safe in practice.
private struct PushPayload: @unchecked Sendable {
    let userInfo: [AnyHashable: Any]
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {

    // MARK: - UIApplicationDelegate

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Wire UNUserNotificationCenter delegate immediately (must be
        // set before `applicationDidFinishLaunching` returns or iOS
        // forgets background-tap delivery).
        UNUserNotificationCenter.current().delegate = self
        registerNotificationCategories()

        // We do NOT call `registerForRemoteNotifications()` here — that
        // happens after the user grants permission in the priming
        // screen (E-app-wire), or right after registration. Calling it
        // pre-permission is a no-op anyway.
        return true
    }

    // MARK: - APNs

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // The APNs payload is the raw 32-byte token. The backend
        // expects base64. (Hex is also common; see
        // `DeviceRegistrationRequest.pushToken` in Models — we ship
        // base64 because it's shorter and the contract documents it as
        // "<base64>".)
        let token = deviceToken.base64EncodedString()
        // RegistrationViewModel still observes this notification so it
        // can stash the token for the in-flight register call.
        NotificationCenter.default.post(
            name: AppNotifications.apnsTokenReceived,
            object: nil,
            userInfo: ["token": token]
        )
        // Once the device is registered, also push the new token to
        // the backend so existing registrations stay reachable.
        Task { @MainActor in
            await AppEnvironment.shared.pushService?.uploadToken(token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NotificationCenter.default.post(
            name: AppNotifications.apnsRegistrationFailed,
            object: nil,
            userInfo: ["error": error]
        )
    }

    /// Silent / data push delivery hook. We only receive real ALERT
    /// pushes, but iOS still calls this for any payload that arrives
    /// while the app is foregrounded. Routed through `PushService` to
    /// the `ScanCoordinator`.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        AppEnvironment.shared.pushService?.handleRemoteNotification(userInfo)
        // No background work to do — we don't fetch in the background
        // (per `50-ios.md` § "Heartbeat" — we explicitly don't use
        // BGAppRefreshTask). Returning `.noData` is correct.
        completionHandler(.noData)
    }

    // MARK: - Notification categories

    private func registerNotificationCategories() {
        // Single category, default tap action only — no actionable
        // buttons, per the App Store review surface minimisation note
        // in `50-ios.md` § "Push handling".
        let category = UNNotificationCategory(
            identifier: scanRequestCategoryIdentifier,
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {

    /// Foreground delivery: show the banner + route the payload
    /// through PushService to the live ScanCoordinator.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        let payload = PushPayload(userInfo: notification.request.content.userInfo)
        Task { @MainActor in
            AppEnvironment.shared.pushService?.handleRemoteNotification(payload.userInfo)
        }
        // Show banner + sound (no list, no badge). The user is
        // already in the app — they can act on the in-UI prompt.
        completionHandler([.banner, .sound])
    }

    /// Tap (or background → app launch) delivery.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let payload = PushPayload(userInfo: response.notification.request.content.userInfo)
        Task { @MainActor in
            AppEnvironment.shared.pushService?.handleRemoteNotification(payload.userInfo)
        }
        completionHandler()
    }
}
