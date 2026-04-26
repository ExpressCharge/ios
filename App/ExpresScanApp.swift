//
//  ExpresScanApp.swift
//  ExpresScan
//
//  SwiftUI App entry-point. We adopt UIKit's `AppDelegate` /
//  `SceneDelegate` pair via `UIApplicationDelegateAdaptor` so we can:
//    - Implement `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
//      (no SwiftUI surface for APNs token receipt).
//    - Implement `scene(_:continue:)` for Universal Link callbacks (see
//      `60-security.md` § 1 — registration callback is a UL, not a custom
//      URL scheme).
//
//  Spec: `50-ios.md` § "Project structure".
//

import SwiftUI

@main
struct ExpresScanApp: App {

    /// Bridges UIKit AppDelegate methods (APNs registration) into SwiftUI.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.app, AppEnvironment.shared)
        }
    }
}
