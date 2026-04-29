//
//  ChargerHero.swift
//  ExpresScan
//
//  Customer-facing hero for the charger detail screen. Composes the
//  Wallbox glyph with one or more J1772 outlines, with a squared
//  cable that exits the bottom of the charger and traces a U
//  underneath both items up to the connector.
//
//  No background — sits on the page chrome. Status colour comes
//  from `ChargerStatusVisuals` (matches the web admin's
//  `device-visuals.ts`).
//

import SwiftUI

struct ChargerHero: View {

    let heroState: StatusHero.State
    let isOffline: Bool
    let connectors: [ChargerDetailViewModel.ConnectorDescriptor]

    private var status: ChargerStatusVisuals.Status {
        ChargerStatusVisuals.status(for: heroState, isOffline: isOffline)
    }

    private var tone: Color { ChargerStatusVisuals.tone(for: status) }
    private var glow: Color { ChargerStatusVisuals.glow(for: status) }

    /// Hero artwork sizing.
    private static let chargerSize: CGFloat = 132
    private static let connectorSize: CGFloat = 96
    private static let cableLineWidth: CGFloat = 8

    var body: some View {
        VStack(spacing: Spacing.sm) {
            artwork
            statusLine
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Charger + cable + connector. Charger sits left, connector
    /// sits right at the same vertical centre, cable forms a U
    /// underneath them.
    private var artwork: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            // Vertical centre line for both glyphs.
            let centerY = (Self.chargerSize / 2) + Spacing.sm
            let chargerCenter = CGPoint(
                x: max(Self.chargerSize / 2 + Spacing.sm, width * 0.28),
                y: centerY
            )
            let connectorCenter = CGPoint(
                x: min(width - Self.connectorSize / 2 - Spacing.sm, width * 0.78),
                y: centerY
            )

            ZStack(alignment: .topLeading) {
                cableShape(
                    chargerCenter: chargerCenter,
                    connectorCenter: connectorCenter,
                    canvasHeight: height
                )
                .stroke(
                    cableColor,
                    style: StrokeStyle(
                        lineWidth: Self.cableLineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                ChargerFormFactorIcon(
                    size: Self.chargerSize,
                    haloColor: tone,
                    glow: glow.opacity(0.45)
                )
                .position(chargerCenter)

                J1772Icon(size: Self.connectorSize)
                    .position(connectorCenter)

                connectorMeta(at: connectorCenter)
            }
        }
        .frame(height: heroArtworkHeight)
    }

    private var heroArtworkHeight: CGFloat {
        // Tall enough to hold the charger + connector at one
        // vertical centre plus the cable U beneath them.
        Self.chargerSize + Self.connectorSize / 2 + Spacing.xl + Spacing.lg
    }

    /// Squared cable: out the bottom of the charger, down a bit,
    /// 90° turn toward the connector, then 90° turn up to the
    /// connector's bottom edge.
    private func cableShape(
        chargerCenter: CGPoint,
        connectorCenter: CGPoint,
        canvasHeight: CGFloat
    ) -> Path {
        var p = Path()
        let chargerBottom = CGPoint(
            x: chargerCenter.x,
            y: chargerCenter.y + Self.chargerSize / 2
        )
        let connectorBottom = CGPoint(
            x: connectorCenter.x,
            y: connectorCenter.y + Self.connectorSize / 2 - 4
        )
        // Run the horizontal segment beneath both glyphs so the
        // turns sit clear of the artwork.
        let runY = max(chargerBottom.y, connectorBottom.y) + Spacing.lg

        p.move(to: chargerBottom)
        p.addLine(to: CGPoint(x: chargerBottom.x, y: runY))
        p.addLine(to: CGPoint(x: connectorBottom.x, y: runY))
        p.addLine(to: connectorBottom)
        return p
    }

    private var cableColor: Color {
        switch status {
        case .charging: return tone.opacity(0.85)
        case .offline:  return ColorPalette.mutedForeground.opacity(0.7)
        default:        return tone.opacity(0.7)
        }
    }

    /// Right-aligned `kW` + connector type label hugging the
    /// connector glyph from the left so it reads as the
    /// connector's spec sheet.
    @ViewBuilder
    private func connectorMeta(at center: CGPoint) -> some View {
        if let descriptor = connectors.first {
            VStack(alignment: .trailing, spacing: 2) {
                Text(kWLabel(for: descriptor))
                    .font(.headline)
                Text(typeLabel(for: descriptor))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .position(
                x: center.x - Self.connectorSize / 2 - 56,
                y: center.y
            )
        }
    }

    /// Status text shown beneath the artwork. Hidden when offline
    /// — the unavailable notice card already explains that state,
    /// so the hero shouldn't re-state it.
    @ViewBuilder
    private var statusLine: some View {
        if let title = statusTitle {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tone)
                .accessibilityHidden(true)
        }
    }

    private var statusTitle: String? {
        switch heroState {
        case .idle:         return "Idle"
        case .plugged:      return "Plugged in"
        case .charging:     return "Charging"
        case .reserved:     return "Reserved"
        case .outOfService:
            // Both offline and faulted hide the hero title — the
            // explanatory card below the hero is the source of
            // truth for unavailable states.
            return nil
        }
    }

    private func kWLabel(for connector: ChargerDetailViewModel.ConnectorDescriptor) -> String {
        guard let kw = connector.maxKw else { return "—" }
        return String(format: "%.0f kW", kw)
    }

    private func typeLabel(for connector: ChargerDetailViewModel.ConnectorDescriptor) -> String {
        connector.connectorType?.displayLabel ?? "—"
    }

    private var accessibilityLabel: String {
        var bits: [String] = []
        if let t = statusTitle { bits.append(t) }
        for c in connectors {
            bits.append("\(typeLabel(for: c)) \(kWLabel(for: c))")
        }
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
