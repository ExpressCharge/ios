//
//  ColorTokens.swift
//  ExpresScan
//
//  Wraps the asset-catalog Color Sets so view code can refer to tokens
//  by an enum case rather than a stringly-typed `Color("PrimaryCyan")`.
//  See `40-frontend.md` § "Design tokens for iOS team" and
//  `docs/design-tokens.json` for the canonical hex values.
//

import SwiftUI

/// Strongly-typed identifiers for every Color Set in the asset catalog.
/// One enum case per `*.colorset` directory under
/// `App/Resources/Assets.xcassets/`.
public enum ColorToken: String, CaseIterable, Sendable {
    case primaryCyan = "PrimaryCyan"
    case voltGreen = "VoltGreen"
    case warningAmber = "WarningAmber"
    case destructiveRose = "DestructiveRose"
    case accentTeal = "AccentTeal"
    case background = "Background"
    case card = "Card"
    case borderSubtle = "BorderSubtle"
}

extension Color {
    /// `Color.token(.primaryCyan)` → `Color("PrimaryCyan", bundle: .main)`.
    public static func token(_ token: ColorToken) -> Color {
        Color(token.rawValue, bundle: .main)
    }
}

// Convenience accessors so view code reads naturally:
//   `.foregroundStyle(.primaryCyan)`
//   `.fill(.background)`
//
// (We can't add static members directly to `Color` without conflicting
// with system colors like `Color.background` introduced in iOS 18, so
// these live as static read-only computed properties on `ColorPalette`,
// not on `Color`.)
public enum ColorPalette {
    public static var primaryCyan: Color { .token(.primaryCyan) }
    public static var voltGreen: Color { .token(.voltGreen) }
    public static var warningAmber: Color { .token(.warningAmber) }
    public static var destructiveRose: Color { .token(.destructiveRose) }
    public static var accentTeal: Color { .token(.accentTeal) }
    public static var background: Color { .token(.background) }
    public static var card: Color { .token(.card) }
    public static var borderSubtle: Color { .token(.borderSubtle) }
}
