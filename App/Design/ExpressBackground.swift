//
//  ExpressBackground.swift
//  ExpresScan
//
//  Single source of truth for the app's page chrome — `ColorPalette
//  .background` (the deep-blue dark / paper light token shipped in
//  `Background.colorset`) painted edge-to-edge, with `Form` / `List`
//  configured to defer to it instead of the system grouped-background.
//
//  Apply via `.expressBackground()` on the leaf view (or a
//  NavigationStack/TabView root) — the modifier is idempotent and
//  cheap; layering it twice is harmless.
//

import SwiftUI

private struct ExpressBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(ColorPalette.background.ignoresSafeArea())
    }
}

public extension View {
    /// Paints the receiver with the brand background colour and tells
    /// any contained `Form` / `List` / `ScrollView` to render its
    /// content over that colour instead of the default system grouped
    /// background. Use at every page root.
    func expressBackground() -> some View {
        modifier(ExpressBackgroundModifier())
    }
}
