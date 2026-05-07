//
//  ChargerPrimaryCard.swift
//  ExpresScan
//
//  Track I5 — proximity-promoted "primary" charger card. Renders the
//  closest charger when the user is within ~150 m, in roughly twice
//  the height of a standard ChargerListRow with a more prominent
//  call-to-action treatment. The remaining chargers fall through to
//  the regular row layout below.
//
//  Status-tone background carries the same green/orange/grey palette
//  as ChargerListRow's `stateBackground`, so the visual signal is
//  consistent across the list — only the size + emphasis differs.
//

import SwiftUI

struct ChargerPrimaryCard: View {

    let entry: ChargerListEntry
    let distanceMeters: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.lg) {
                ChargerFormFactorIcon(
                    size: 84,
                    formFactor: entry.formFactor,
                    haloColor: ChargerStatusVisuals.tone(
                        for: ChargerStatusVisuals.status(
                            from: entry.state ?? .idle
                        )
                    ),
                    glow: ChargerStatusVisuals.glow(
                        for: ChargerStatusVisuals.status(
                            from: entry.state ?? .idle
                        )
                    ).opacity(0.5)
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Right here")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ColorPalette.primaryCyan)
                        .textCase(.uppercase)
                        .tracking(1)
                    Text(entry.label)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let site = entry.siteName, !site.isEmpty {
                        Text(site)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let m = distanceMeters {
                        Text(formatDistance(m))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
                if let pid = entry.publicId {
                    PublicIdView(publicId: pid, size: .regular)
                }
            }
            HStack(spacing: Spacing.sm) {
                if entry.isUnmanaged {
                    CapabilityPill(
                        label: "Free",
                        systemImage: "bolt.fill",
                        tone: .free
                    )
                } else {
                    CapabilityPill(
                        label: "Mobile Start",
                        systemImage: "iphone",
                        tone: .mobile
                    )
                    if let state = entry.state {
                        CapabilityPill(
                            label: state.displayLabel,
                            systemImage: stateSymbol(for: state),
                            tone: tone(for: state)
                        )
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ColorPalette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    ChargerStatusVisuals.tone(
                        for: ChargerStatusVisuals.status(
                            from: entry.state ?? .idle
                        )
                    ).opacity(0.5),
                    lineWidth: 2
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - Helpers

    private func formatDistance(_ metres: Double) -> String {
        let feet = metres * 3.28084
        if feet < 1000 {
            return String(format: "%.0f ft away", feet)
        }
        let miles = metres / 1609.344
        return miles < 10
            ? String(format: "%.1f mi away", miles)
            : String(format: "%.0f mi away", miles)
    }

    private func stateSymbol(for state: ChargerListEntry.ChargerState) -> String {
        switch state {
        case .charging: return "bolt.fill"
        case .preparing: return "powerplug"
        case .reserved: return "calendar"
        case .outOfService: return "exclamationmark.triangle.fill"
        case .offline: return "wifi.slash"
        case .idle: return "bolt"
        }
    }

    private func tone(for state: ChargerListEntry.ChargerState) -> CapabilityPill.Tone {
        switch state {
        case .charging: return .scanner
        case .reserved: return .mobile
        case .offline, .outOfService: return .neutral
        default: return .neutral
        }
    }

    private var accessibilitySummary: String {
        var parts: [String] = ["Right here", entry.label]
        if let m = distanceMeters {
            parts.append(formatDistance(m))
        }
        if entry.isUnmanaged {
            parts.append("Free charging")
        } else if let s = entry.state {
            parts.append(s.displayLabel)
        }
        return parts.joined(separator: ", ")
    }
}
