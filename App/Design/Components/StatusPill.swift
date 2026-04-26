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

import SwiftUI

public struct StatusPill: View {

    public enum Tone: Equatable, Sendable {
        case positive
        case warning
        case negative
        case neutral
        case info

        var color: Color {
            switch self {
            case .positive: return ColorPalette.voltGreen
            case .warning:  return ColorPalette.warningAmber
            case .negative: return ColorPalette.destructiveRose
            case .neutral:  return ColorPalette.borderSubtle
            case .info:     return ColorPalette.accentTeal
            }
        }
    }

    public let label: String
    public let systemImage: String
    public let tone: Tone

    public init(label: String, systemImage: String, tone: Tone) {
        self.label = label
        self.systemImage = systemImage
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .foregroundStyle(.primary)
        .background(
            Capsule(style: .continuous)
                .fill(tone.color.opacity(0.15))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tone.color.opacity(0.40), lineWidth: 1)
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
