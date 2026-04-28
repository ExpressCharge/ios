//
//  ChargerListRow.swift
//  ExpresScan
//
//  Wave 6 / Slice I — single row in the Chargers list. Form-factor
//  icon, label, optional site/kW caption, and a trailing `StatusPill`
//  for the online state. Sized for native `List` rendering at any
//  Dynamic Type level.
//

import SwiftUI

struct ChargerListRow: View {

    let entry: ChargerListEntry

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            iconView
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
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
            }
            .layoutPriority(1)

            Spacer(minLength: Spacing.sm)

            StatusPill(
                label: entry.state.displayLabel,
                systemImage: entry.state.systemImage,
                tone: entry.state.pillTone
            )
            .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var iconView: some View {
        Image(systemName: entry.formFactor.systemImage)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(ColorPalette.primaryCyan)
            .font(.system(size: 22, weight: .regular))
    }

    private var captionText: String? {
        var bits: [String] = []
        if let site = entry.siteName, !site.isEmpty { bits.append(site) }
        if let kw = entry.maxKw {
            bits.append(String(format: "%.0f kW", kw))
        }
        return bits.isEmpty ? nil : bits.joined(separator: " · ")
    }

    private var accessibilitySummary: String {
        var bits: [String] = [entry.label, entry.state.displayLabel]
        if let site = entry.siteName { bits.append(site) }
        if let kw = entry.maxKw { bits.append("\(Int(kw)) kilowatts") }
        return bits.joined(separator: ", ")
    }
}

private extension ChargerListEntry.FormFactor {
    /// SF Symbol shown in the row leading position. iOS 26 doesn't ship
    /// per-form-factor icons; the generic `ev.charger` reads cleanly
    /// across all five.
    var systemImage: String { "ev.charger" }
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
