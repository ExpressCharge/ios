//
//  KioskShell.swift
//  ExpresScan
//
//  Wave 6 / Slice F. Generic chrome-stripped wrapper used when
//  `kiosk ∈ capabilities`. Hides the navigation toolbar, persistent
//  system overlays (volume HUD, etc.), and the status bar so a kiosked
//  iPad/iPhone presents only the lone capability's screen.
//
//  Sign-out is impossible from the device under kiosk — only via the
//  web admin remote-deregister. The on-device escape gesture (5-tap
//  on a corner → Diagnostics) lands in slice K3.
//

import SwiftUI

/// Chrome-stripped wrapper for kiosk mode. Hides the toolbar,
/// persistent system overlays, and the status bar.
public struct KioskShell<Content: View>: View {

    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .toolbar(.hidden, for: .navigationBar, .tabBar)
            .persistentSystemOverlays(.hidden)
            .statusBarHidden(true)
    }
}
