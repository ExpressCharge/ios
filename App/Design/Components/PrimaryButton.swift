//
//  PrimaryButton.swift
//  ExpresScan
//
//  Shared primary-CTA wrapper. Wires `.buttonStyle(.glass)` (iOS 26
//  Liquid Glass) with a tone-tinted accent so callers can write
//  `PrimaryButton(.primary)` instead of duplicating background, padding,
//  and accessibility identifiers across feature views.
//
//  Variants mirror the web `<Button>` shadcn variants:
//    - `.primary`     → cyan, default action
//    - `.success`     → green, confirm-active states (e.g. "Tap to scan")
//    - `.destructive` → rose, destructive actions (e.g. sign-out)
//
//  States cover the common UI lifecycles:
//    - `.default`  — tappable
//    - `.loading`  — shows ProgressView, button disabled
//    - `.disabled` — explicitly disabled
//

import SwiftUI

public struct PrimaryButton: View {

    public enum Variant: Sendable {
        case primary
        case success
        case destructive

        var tint: Color {
            switch self {
            case .primary: return ColorPalette.primaryCyan
            case .success: return ColorPalette.success
            case .destructive: return ColorPalette.destructiveRose
            }
        }
    }

    public enum State: Sendable {
        case `default`
        case loading
        case disabled

        var isInteractive: Bool {
            self == .default
        }
    }

    /// Visual size of the CTA. `.standard` is the everyday 44pt-tall
    /// button used throughout settings + auth flows. `.hero` is the
    /// car-app-style ~80pt-tall variant used by the customer-grade
    /// charger Start/Stop buttons (Slice J). Don't introduce a third —
    /// extend this enum if more sizes are needed.
    public enum Size: Sendable {
        case standard
        case hero

        var minHeight: CGFloat {
            switch self {
            case .standard: return 44
            case .hero: return 80
            }
        }

        var labelFont: Font {
            switch self {
            case .standard: return .headline
            case .hero: return .title2.weight(.semibold)
            }
        }

        var iconFont: Font {
            switch self {
            case .standard: return .body
            case .hero: return .system(size: 28, weight: .semibold)
            }
        }

        var hSpacing: CGFloat {
            switch self {
            case .standard: return Spacing.sm
            case .hero: return Spacing.md
            }
        }
    }

    public let label: String
    public let systemImage: String?
    public let variant: Variant
    public let state: State
    public let size: Size
    public let action: () -> Void

    public init(
        _ label: String,
        systemImage: String? = nil,
        variant: Variant = .primary,
        state: State = .default,
        size: Size = .standard,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.variant = variant
        self.state = state
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: size.hSpacing) {
                if state == .loading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(size == .hero ? .large : .small)
                        .tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(size.iconFont)
                }
                Text(label)
                    .font(size.labelFont)
            }
            .frame(maxWidth: .infinity, minHeight: size.minHeight)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .tint(variant.tint)
        .disabled(!state.isInteractive)
        .accessibilityIdentifier("primaryButton_\(label)")
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 16) {
        PrimaryButton("Sign in to ExpressCharge", action: {})
        PrimaryButton("Tap to scan", systemImage: "wave.3.right", variant: .success, action: {})
        PrimaryButton("Sign out", variant: .destructive, action: {})
        PrimaryButton("Loading", state: .loading, action: {})
        PrimaryButton("Disabled", state: .disabled, action: {})
    }
    .padding()
}
#endif
