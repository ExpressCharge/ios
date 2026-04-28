//
//  SettingsToolbarMenuButton.swift
//  ExpresScan
//
//  Wave 6 / Slice F. Single Settings toolbar entry — top-right gear on
//  every screen except kiosk. Tapping pushes `SettingsView` via
//  `NavigationLink` (per the UX research recommendation: native push,
//  not sheet, on iOS 26).
//
//  Exposed as a `View` extension `.expressScanToolbarMenu()` so any
//  feature view can opt-in with a single line.
//

import SwiftUI

/// Top-right toolbar entry: a `NavigationLink` rendered as a gear icon
/// pushing into `SettingsView`. Used by every non-kiosk screen.
public struct SettingsToolbarMenuButton: ToolbarContent {

    public init() {}

    public var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
                    .accessibilityLabel("Settings")
            }
        }
    }
}

public extension View {
    /// Adds the `SettingsToolbarMenuButton` to the receiver's toolbar.
    /// Caller must already be inside a `NavigationStack`.
    func expressScanToolbarMenu() -> some View {
        self.toolbar { SettingsToolbarMenuButton() }
    }
}
