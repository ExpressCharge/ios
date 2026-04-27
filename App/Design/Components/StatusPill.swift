//
//  StatusPill.swift
//  ExpresScan
//
//  Small status badge: SF Symbol + label. Color is one of the design
//  tokens, BUT — per `60-security.md` § accessibility recommendations
//  and Apple HIG — color is NEVER the only signal. Every variant
//  carries a distinct icon AND a distinct word, so VoiceOver and
//  color-blind users get the same information channel.
//
//  Used on the home screen ("Online", "Offline", "Connecting"…) and
//  the success card ("Active", "Pending", "Terminated"…).
//
//  Visual treatment mirrors the ExpresSync web `StatusBadge`
//  (`expressync/components/shared/StatusBadge.tsx`): a tinted-glass
//  capsule whose tint comes from a semantic color token.
//

import SwiftUI

public struct StatusPill: View {

    public enum Tone: Equatable, Sendable {
        case positive
        case warning
        case negative
        case neutral
        case info

        /// Fill / stroke / glass-tint color.
        var fillColor: Color {
            switch self {
            case .positive: return ColorPalette.success
            case .warning:  return ColorPalette.warningAmber
            case .negative: return ColorPalette.destructiveRose
            case .neutral:  return ColorPalette.mutedForeground
            case .info:     return ColorPalette.info
            }
        }

        /// Text + icon color. Web pattern: `text-{tone}-700` light /
        /// `text-{tone}-400` dark. iOS asset catalogs already encode
        /// both luminosity variants, so we read straight from the
        /// matching token.
        var textColor: Color {
            switch self {
            case .positive: return ColorPalette.success
            case .warning:  return ColorPalette.warningAmber
            case .negative: return ColorPalette.destructiveRose
            case .neutral:  return ColorPalette.mutedForeground
            case .info:     return ColorPalette.info
            }
        }
    }

    public let label: String
    public let systemImage: String
    public let tone: Tone
    public let iconOpacity: Double

    public init(
        label: String,
        systemImage: String,
        tone: Tone,
        iconOpacity: Double = 1.0
    ) {
        self.label = label
        self.systemImage = systemImage
        self.tone = tone
        self.iconOpacity = iconOpacity
    }

    public var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .opacity(iconOpacity)
                .accessibilityHidden(true)
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .foregroundStyle(tone.textColor)
        .background(
            // iOS 26 Liquid Glass with a tone-tinted hue. Falls back
            // to a translucent fill on older OS, but we now ship at
            // iOS 26 only.
            Capsule(style: .continuous)
                .glassEffect(.regular.tint(tone.fillColor.opacity(0.20)))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) status")
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 12) {
        StatusPill(label: "Online", systemImage: "checkmark.circle.fill", tone: .positive)
        StatusPill(label: "Connecting", systemImage: "arrow.triangle.2.circlepath", tone: .info)
        StatusPill(label: "Offline", systemImage: "wifi.slash", tone: .negative)
        StatusPill(label: "Pending", systemImage: "hourglass", tone: .warning)
        StatusPill(label: "Idle", systemImage: "moon.zzz", tone: .neutral)
    }
    .padding()
}
#endif
