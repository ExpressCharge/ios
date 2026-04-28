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
        HStack(alignment: .top, spacing: Spacing.md) {
            ChargerFormFactorIcon(size: 56, haloColor: haloColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.label)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                    .truncationMode(.tail)

                if let caption = captionText {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                // Capability pills sit above the state line so the
                // bottom of the row reads top-down: "what this card
                // can do" → "what this card is doing right now".
                // Mobile Start is shown on every charger (all OCPP
                // chargers support RemoteStartTransaction); NFC is
                // shown when the row carries the `scanner` capability.
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

                HStack(spacing: 6) {
                    Image(systemName: entry.state.systemImage)
                        .font(.caption2)
                        .foregroundStyle(stateForeground)
                    Text(entry.state.displayLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // Inset to align the state-icon with the pill text
                // (pills carry 8pt internal padding; matching that
                // here keeps the bottom of the card on a single
                // visual baseline) and add a small top breathing
                // room so the line lifts off the pills.
                .padding(.leading, 4)
                .padding(.top, 4)
            }
            .frame(minHeight: 72, alignment: .topLeading)
            .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
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
