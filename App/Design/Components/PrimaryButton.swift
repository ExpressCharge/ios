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
            case .primary:     return ColorPalette.primaryCyan
            case .success:     return ColorPalette.success
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

    public let label: String
    public let systemImage: String?
    public let variant: Variant
    public let state: State
    public let action: () -> Void

    public init(
        _ label: String,
        systemImage: String? = nil,
        variant: Variant = .primary,
        state: State = .default,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.variant = variant
        self.state = state
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if state == .loading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(label)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
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
