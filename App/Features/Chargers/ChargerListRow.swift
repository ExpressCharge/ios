//
//  ChargerListRow.swift
//  ExpresScan
//
//  Wave 6 / Slice I — single row in the Chargers list. Uses the
//  Wallbox-style `ChargerFormFactorIcon` with a status-coloured halo
//  (mirroring the web admin's `ChargerCard` icon treatment), plus a
//  richer two-line caption (site · connector · max kW), an inline
//  state line, and a trailing `StatusPill` for the online state.
//

import SwiftUI

struct ChargerListRow: View {

    let entry: ChargerListEntry

    var body: some View {
        rowContent
            .padding(.vertical, Spacing.lg)
            .padding(.horizontal, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(stateBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(stateBorderColor, lineWidth: stateBorderWidth)
            )
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: Spacing.lg) {
            ChargerFormFactorIcon(size: 56, haloColor: haloColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.label)
                    .font(.headline)
                    .lineLimit(2)
                    .truncationMode(.tail)

                if let caption = captionText {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Bottom row: capability pills, left-aligned. The
                // charger's status is already encoded by the icon
                // halo (and reinforced by the card's tinted bg +
                // border), so a separate state line would be
                // redundant noise.
                HStack(spacing: 6) {
                    CapabilityPill(
                        label: "Mobile Start",
                        systemImage: "iphone",
                        tone: .mobile
                    )
                    if hasScannerCapability {
                        CapabilityPill(
                            label: "NFC",
                            systemImage: "wave.3.right.circle.fill",
                            tone: .scanner
                        )
                    }
                }
                .padding(.top, Spacing.sm)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - Status-reactive card styling
    //
    // Per user direction:
    //   - charging      → voltGreen-tinted bg over the card surface
    //   - idle/avail.   → standard card bg, primary-cyan accent
    //                     already lives in the icon halo / state line
    //   - preparing     → standard card bg (waiting to charge)
    //   - reserved      → standard card bg, orange halo carries state
    //   - outOfService  → grey-blue disabled bg with a red border —
    //                     looks "broken / don't tap"
    //   - offline       → standard card bg with a darker border so
    //                     the card reads as inactive without a tinted
    //                     background

    private var stateBackground: Color {
        switch entry.state {
        case .charging:
            return ColorPalette.voltGreen.opacity(0.12)
        case .outOfService:
            return Color(red: 0.16, green: 0.18, blue: 0.22)
        case .offline:
            return ColorPalette.card
        case .idle, .preparing, .reserved:
            return ColorPalette.card
        }
    }

    private var stateBorderColor: Color {
        switch entry.state {
        case .charging:
            return ColorPalette.voltGreen.opacity(0.40)
        case .outOfService:
            return Color.red.opacity(0.55)
        case .offline:
            return Color.white.opacity(0.18)
        case .idle, .preparing, .reserved:
            return ColorPalette.borderSubtle
        }
    }

    private var stateBorderWidth: CGFloat {
        switch entry.state {
        case .outOfService: return 1.5
        case .offline:      return 1.5
        case .charging:     return 1.5
        default:            return 1
        }
    }

    /// Halo colour mirrors the StatusPill tone — green for charging,
    /// teal-cyan for available/reserved, amber for stale/preparing,
    /// red for offline/faulted.
    private var haloColor: Color {
        switch entry.state {
        case .charging:       return ColorPalette.voltGreen
        case .idle:           return ColorPalette.primaryCyan
        case .preparing:      return ColorPalette.primaryCyan
        case .reserved:       return .orange
        case .outOfService:   return .yellow
        case .offline:        return .red
        }
    }

    private var stateForeground: Color {
        switch entry.state {
        case .charging:       return ColorPalette.voltGreen
        case .idle, .preparing: return ColorPalette.primaryCyan
        case .reserved:       return .orange
        case .outOfService:   return .yellow
        case .offline:        return .secondary
        }
    }

    /// `true` when the charger advertises the `scanner` capability —
    /// drives the NFC pill rendering. Tolerates the field being
    /// missing on older server builds (treated as no NFC).
    private var hasScannerCapability: Bool {
        entry.capabilities?.contains("scanner") ?? false
    }

    private var captionText: String? {
        var bits: [String] = []
        if let site = entry.siteName, !site.isEmpty { bits.append(site) }
        if let connector = entry.connectorType?.displayLabel {
            bits.append(connector)
        }
        if let kw = entry.maxKw {
            bits.append(String(format: "%.0f kW", kw))
        }
        return bits.isEmpty ? nil : bits.joined(separator: " · ")
    }

    private var stateLine: String {
        if let lastSeen = entry.lastSeenAt {
            let rel = Self.relative.localizedString(for: lastSeen, relativeTo: Date())
            return "\(entry.state.displayLabel) · \(rel)"
        }
        return entry.state.displayLabel
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private var accessibilitySummary: String {
        var bits: [String] = [entry.label, entry.state.displayLabel]
        if let site = entry.siteName { bits.append(site) }
        if let connector = entry.connectorType?.displayLabel { bits.append(connector) }
        if let kw = entry.maxKw { bits.append("\(Int(kw)) kilowatts") }
        return bits.joined(separator: ", ")
    }
}

private extension ChargerListEntry.ConnectorType {
    var displayLabel: String {
        switch self {
        case .ccs:     return "CCS"
        case .j1772:   return "J1772"
        case .nacs:    return "NACS"
        case .chademo: return "CHAdeMO"
        case .type2:   return "Type 2"
        }
    }
}

private extension ChargerListEntry.ChargerState {
    var systemImage: String {
        switch self {
        case .idle:           return "checkmark.circle.fill"
        case .preparing:      return "powerplug.fill"
        case .charging:       return "bolt.fill"
        case .reserved:       return "clock.fill"
        case .outOfService:   return "exclamationmark.triangle.fill"
        case .offline:        return "wifi.slash"
        }
    }

    var pillTone: StatusPill.Tone {
        switch self {
        case .idle:           return .neutral
        case .preparing:      return .info
        case .charging:       return .positive
        case .reserved:       return .info
        case .outOfService:   return .warning
        case .offline:        return .negative
        }
    }
}
