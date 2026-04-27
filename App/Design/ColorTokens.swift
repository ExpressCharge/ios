//
//  ColorTokens.swift
//  ExpresScan
//
//  Wraps the asset-catalog Color Sets so view code can refer to tokens
//  by an enum case rather than a stringly-typed `Color("PrimaryCyan")`.
//
//  Tokens are computed from the canonical OKLch values published by the
//  ExpresSync web design system at
//  `expressync/assets/styles.css`'s `:root` and `.dark` blocks. The
//  conversion to Display P3 happens once at asset-catalog build time;
//  see COLORS.md for the verbatim mapping.
//

import SwiftUI

/// Strongly-typed identifiers for every Color Set in the asset catalog.
/// One enum case per `*.colorset` directory under
/// `App/Resources/Assets.xcassets/`.
public enum ColorToken: String, CaseIterable, Sendable {
    // MARK: Brand
    case primaryCyan = "PrimaryCyan"
    case voltGreen = "VoltGreen"

    // MARK: Semantic
    case success = "Success"
    case info = "Info"
    case warningAmber = "WarningAmber"
    case destructiveRose = "DestructiveRose"

    // MARK: Surface
    case background = "Background"
    case card = "Card"
    case muted = "Muted"

    // MARK: Text
    case foreground = "Foreground"
    case mutedForeground = "MutedForeground"

    // MARK: Borders
    case borderSubtle = "BorderSubtle"

    // MARK: Decorative glow
    case glowCyan = "GlowCyan"
    case glowGreen = "GlowGreen"
    case glowViolet = "GlowViolet"
}

extension Color {
    /// `Color.token(.primaryCyan)` → `Color("PrimaryCyan", bundle: .main)`.
    public static func token(_ token: ColorToken) -> Color {
        Color(token.rawValue, bundle: .main)
    }
}

/// Convenience accessors so view code reads naturally:
///   `.foregroundStyle(ColorPalette.primaryCyan)`
///   `.fill(ColorPalette.background)`
///
/// (We can't add static members directly to `Color` without conflicting
/// with system colors like `Color.background` introduced in iOS 18, so
/// these live as static read-only computed properties on `ColorPalette`,
/// not on `Color`.)
public enum ColorPalette {
    public static var primaryCyan: Color { .token(.primaryCyan) }
    public static var voltGreen: Color { .token(.voltGreen) }
    public static var success: Color { .token(.success) }
    public static var info: Color { .token(.info) }
    public static var warningAmber: Color { .token(.warningAmber) }
    public static var destructiveRose: Color { .token(.destructiveRose) }
    public static var background: Color { .token(.background) }
    public static var card: Color { .token(.card) }
    public static var muted: Color { .token(.muted) }
    public static var foreground: Color { .token(.foreground) }
    public static var mutedForeground: Color { .token(.mutedForeground) }
    public static var borderSubtle: Color { .token(.borderSubtle) }
    public static var glowCyan: Color { .token(.glowCyan) }
    public static var glowGreen: Color { .token(.glowGreen) }
    public static var glowViolet: Color { .token(.glowViolet) }
}
