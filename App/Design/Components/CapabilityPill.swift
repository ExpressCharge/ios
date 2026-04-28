//
//  CapabilityPill.swift
//  ExpresScan
//
//  Compact tinted pill matching the web's CapabilityPill /
//  StatusPill vocabulary:
//
//      border-{color}/30 + bg-{color}/10 + text-{color}-300 (dark)
//
//  In SwiftUI that maps to a `Capsule` with a tinted background
//  (~10% opacity), a stroke at ~30% opacity, and a foreground
//  brightened to the same hue at ~85% lightness so the label stays
//  legible against the deep-blue page background.
//

import SwiftUI

public struct CapabilityPill: View {

    public enum Tone: Sendable {
        case scanner   // teal
        case charger   // orange
        case user      // cyan
        case kiosk     // violet
        case mobile    // primary cyan — Mobile Start
        case neutral   // slate
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
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tone.text)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(tone.tint.opacity(0.10))
        )
        .overlay(
            Capsule().strokeBorder(tone.tint.opacity(0.30), lineWidth: 1)
        )
        .accessibilityLabel(label)
    }
}

private extension CapabilityPill.Tone {
    /// Base hue. Used for the bg/border tint.
    var tint: Color {
        switch self {
        case .scanner: return .teal
        case .charger: return .orange
        case .user:    return .cyan
        case .kiosk:   return .purple
        case .mobile:  return ColorPalette.primaryCyan
        case .neutral: return .gray
        }
    }

    /// Text colour — the same hue as `tint` but bright enough to read
    /// against the page background (matches Tailwind's `text-{color}-300`
    /// pattern in dark mode).
    var text: Color {
        switch self {
        case .scanner: return Color(red: 0.36, green: 0.87, blue: 0.86)  // teal-300
        case .charger: return Color(red: 0.99, green: 0.78, blue: 0.41)  // orange-300
        case .user:    return Color(red: 0.40, green: 0.90, blue: 0.96)  // cyan-300
        case .kiosk:   return Color(red: 0.78, green: 0.65, blue: 0.99)  // violet-300
        case .mobile:  return ColorPalette.primaryCyan
        case .neutral: return Color(red: 0.80, green: 0.83, blue: 0.87)  // slate-300
        }
    }
}

#if DEBUG
#Preview("Pills") {
    HStack(spacing: 8) {
        CapabilityPill(label: "Mobile Start", systemImage: "bolt.fill", tone: .mobile)
        CapabilityPill(label: "NFC", systemImage: "wave.3.right.circle.fill", tone: .scanner)
        CapabilityPill(label: "Charger", systemImage: "ev.charger", tone: .charger)
    }
    .padding()
    .background(Color.black)
}
#endif
