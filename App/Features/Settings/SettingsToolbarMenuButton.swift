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

/// Toolbar entries for every non-kiosk screen:
///   - top-left: the `BrandLockup(.compact)` (logo + ExpressCharge
///     wordmark). Rendered as plain `Image`+`Text` so it has no
///     button affordance — purely a brand mark.
///   - top-right: a `NavigationLink` rendered as a gear icon that
///     pushes `SettingsView`.
public struct SettingsToolbarMenuButton: ToolbarContent {

    public init() {}

    public var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            BrandLockup(.compact)
                // Defensive: ToolbarItem can render its child with a
                // tappable affordance on some iOS-26 toolbar layouts.
                // Disabling lets the system know this is a static
                // brand mark, not an action.
                .allowsHitTesting(false)
                .accessibilityAddTraits(.isHeader)
        }
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
