//
//  Theme.swift
//  ExpresScan
//
//  Aggregates the design-token primitives — colors, spacing, radius,
//  typography — into a single value plumbed through the SwiftUI
//  environment. Mirrors the ExpresSync web `:root` / `.dark` token set.
//
//  Spec: `40-frontend.md` § "Design tokens for iOS team" + COLORS.md.
//

import SwiftUI

/// Spacing tokens (pt). Matches the JSON tokens 1:1.
public enum Spacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let base: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
}

/// Corner-radius tokens (pt).
public enum Radius {
    public static let sm: CGFloat = 6
    public static let md: CGFloat = 8
    public static let lg: CGFloat = 10
    public static let xl: CGFloat = 14
    /// Use for fully rounded pills.
    public static let pill: CGFloat = 999
}

/// Typography uses the system stack (`-apple-system`) on iOS — no
/// custom font registration required. Monospace is used in the
/// diagnostics sheet.
public enum Typography {
    public static let monoStack = "Menlo"
}

/// Single, immutable theme value. Pass-by-value through SwiftUI's
/// `EnvironmentValues`. Mostly here so future re-skins (e.g. high
/// contrast) can swap the `Theme` from above the affected subtree
/// without rewriting consumer code.
public struct Theme: Sendable {
    public let colors: Colors
    public let spacing: SpacingTokens
    public let radius: RadiusTokens

    public init(
        colors: Colors = .default,
        spacing: SpacingTokens = .default,
        radius: RadiusTokens = .default
    ) {
        self.colors = colors
        self.spacing = spacing
        self.radius = radius
    }

    public static let `default` = Theme()

    public struct Colors: Sendable {
        public let primaryCyan: ColorToken
        public let voltGreen: ColorToken
        public let success: ColorToken
        public let info: ColorToken
        public let warningAmber: ColorToken
        public let destructiveRose: ColorToken
        public let background: ColorToken
        public let card: ColorToken
        public let muted: ColorToken
        public let foreground: ColorToken
        public let mutedForeground: ColorToken
        public let borderSubtle: ColorToken
        public let glowCyan: ColorToken
        public let glowGreen: ColorToken
        public let glowViolet: ColorToken

        public static let `default` = Colors(
            primaryCyan: .primaryCyan,
            voltGreen: .voltGreen,
            success: .success,
            info: .info,
            warningAmber: .warningAmber,
            destructiveRose: .destructiveRose,
            background: .background,
            card: .card,
            muted: .muted,
            foreground: .foreground,
            mutedForeground: .mutedForeground,
            borderSubtle: .borderSubtle,
            glowCyan: .glowCyan,
            glowGreen: .glowGreen,
            glowViolet: .glowViolet
        )
    }

    public struct SpacingTokens: Sendable {
        public let xs: CGFloat
        public let sm: CGFloat
        public let md: CGFloat
        public let base: CGFloat
        public let lg: CGFloat
        public let xl: CGFloat

        public static let `default` = SpacingTokens(
            xs: Spacing.xs, sm: Spacing.sm, md: Spacing.md,
            base: Spacing.base, lg: Spacing.lg, xl: Spacing.xl
        )
    }

    public struct RadiusTokens: Sendable {
        public let sm: CGFloat
        public let md: CGFloat
        public let lg: CGFloat
        public let xl: CGFloat
        public let pill: CGFloat

        public static let `default` = RadiusTokens(
            sm: Radius.sm, md: Radius.md, lg: Radius.lg,
            xl: Radius.xl, pill: Radius.pill
        )
    }

    /// Convenience: `Theme.color(.primaryCyan)`. Reads from the
    /// asset catalog, honoring light/dark.
    public static func color(_ token: ColorToken) -> Color {
        Color.token(token)
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .default
}

extension EnvironmentValues {
    /// Access via `@Environment(\.theme) private var theme`.
    public var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
