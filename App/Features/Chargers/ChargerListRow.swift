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
    /// Distance in metres from the user's current location, when
    /// known. Rendered as a dimmed top-right caption (e.g. "0.4 mi").
    /// Track I5; nil hides the label entirely.
    var distanceMeters: Double? = nil

    init(entry: ChargerListEntry, distanceMeters: Double? = nil) {
        self.entry = entry
        self.distanceMeters = distanceMeters
    }

    var body: some View {
        rowContent
            .padding(Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(stateBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(stateBorderColor, lineWidth: stateBorderWidth)
            )
            .overlay(alignment: .topTrailing) {
                if let m = distanceMeters {
                    Text(formatDistance(m))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, Spacing.sm)
                        .padding(.trailing, Spacing.md)
                }
            }
    }

    private func formatDistance(_ metres: Double) -> String {
        // Imperial for the iOS audience — mi/ft. The threshold
        // mirrors the primary-card rule (<150 m feels like "right
        // here") so values below it always show as "<X ft".
        let feet = metres * 3.28084
        if feet < 1000 {
            return String(format: "%.0f ft", feet)
        }
        let miles = metres / 1609.344
        if miles < 10 {
            return String(format: "%.1f mi", miles)
        }
        return String(format: "%.0f mi", miles)
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: Spacing.lg) {
            ChargerFormFactorIcon(
                size: 56,
                formFactor: entry.formFactor,
                haloColor: haloColor
            )

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
                    if isUnmanaged {
                        // Migration 0043 — unmanaged chargers don't
                        // have remote-start; the pill telegraphs that
                        // the unit is free to use without the app.
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
                    }
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

            // Track I3 — replaces the row's trailing chevron with the
            // charger's 8-char public ID rendered in the same 4×4
            // green-letters / blue-digits format printed on the
            // sticker. Acts as a quiet identity watermark so the
            // operator can match a row to a card at a glance.
            if let pid = entry.publicId {
                PublicIdView(publicId: pid, size: .small)
                    .padding(.leading, Spacing.sm)
            }
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

    /// Coarse status used to look up tone/glow via the central
    /// `ChargerStatusVisuals` helper — keeps list and detail aligned.
    /// Unmanaged chargers don't carry a state on the wire (Track W7);
    /// fall back to `.available` so the row reads as a usable charger
    /// rather than offline.
    private var status: ChargerStatusVisuals.Status {
        ChargerStatusVisuals.status(from: entry.state ?? .idle)
    }

    private var stateBackground: Color {
        switch status {
        case .charging: return ColorPalette.voltGreen.opacity(0.12)
        case .unavailable: return Color(red: 0.16, green: 0.18, blue: 0.22)
        case .available, .reserved, .offline:
            return ColorPalette.card
        }
    }

    private var stateBorderColor: Color {
        switch status {
        case .charging: return ColorPalette.voltGreen.opacity(0.40)
        case .unavailable: return ColorPalette.destructiveRose.opacity(0.55)
        case .offline: return Color.white.opacity(0.18)
        case .available, .reserved:
            return ColorPalette.borderSubtle
        }
    }

    private var stateBorderWidth: CGFloat {
        switch status {
        case .unavailable, .offline, .charging: return 1.5
        case .available, .reserved: return 1
        }
    }

    private var haloColor: Color {
        ChargerStatusVisuals.tone(for: status)
    }

    /// `true` when the charger advertises the `scanner` capability —
    /// drives the NFC pill rendering. Tolerates the field being
    /// missing on older server builds (treated as no NFC).
    private var hasScannerCapability: Bool {
        entry.capabilities?.contains("scanner") ?? false
    }

    /// `true` when the charger is administered outside StEvE (Tesla
    /// Wall Connectors etc.). Migration 0043. Older server builds omit
    /// the field; treat absence as `.ocpp`.
    private var isUnmanaged: Bool {
        entry.managementMode == .unmanaged
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

extension ChargerListEntry.ConnectorType {
    fileprivate var displayLabel: String {
        switch self {
        case .ccs: return "CCS"
        case .j1772: return "J1772"
        case .nacs: return "NACS"
        case .chademo: return "CHAdeMO"
        case .type2: return "Type 2"
        }
    }
}

extension ChargerListEntry.ChargerState {
    fileprivate var systemImage: String {
        switch self {
        case .idle: return "checkmark.circle.fill"
        case .preparing: return "powerplug.fill"
        case .charging: return "bolt.fill"
        case .reserved: return "clock.fill"
        case .outOfService: return "exclamationmark.triangle.fill"
        case .offline: return "wifi.slash"
        }
    }

    fileprivate var pillTone: StatusPill.Tone {
        switch self {
        case .idle: return .neutral
        case .preparing: return .info
        case .charging: return .positive
        case .reserved: return .info
        case .outOfService: return .warning
        case .offline: return .negative
        }
    }
}
