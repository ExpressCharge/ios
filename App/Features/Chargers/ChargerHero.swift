//
//  ChargerHero.swift
//  ExpresScan
//
//  Customer-facing hero for the charger detail screen. Composes the
//  Wallbox glyph with one or more connector glyphs, drawing a squared
//  cable between them (down out of the charger's bottom, across, then
//  up to the connector port).
//
//  Status colour comes from `ChargerStatusVisuals` (matches the web
//  admin's `device-visuals.ts`). The hero itself has no background —
//  it sits transparently on the page chrome.
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

    /// Hero artwork sizing. The charger glyph reads as the dominant
    /// element; the connector(s) sit alongside.
    private static let chargerSize: CGFloat = 132
    private static let connectorSize: CGFloat = 88
    private static let cableLineWidth: CGFloat = 8

    var body: some View {
        VStack(spacing: Spacing.md) {
            artwork
            statusLine
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Charger + cable + connector. Layout uses fixed proportions so
    /// the cable's right-angle turns line up with the charger's
    /// bottom edge and the connector's left edge regardless of
    /// container width.
    private var artwork: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            // Charger anchored upper-left.
            let chargerCenter = CGPoint(
                x: max(Self.chargerSize / 2 + 4, width * 0.22),
                y: Self.chargerSize / 2 + 4
            )
            // Connector anchored lower-right.
            let connectorCenter = CGPoint(
                x: min(width - Self.connectorSize / 2 - 4, width * 0.78),
                y: height - Self.connectorSize / 2 - 4
            )

            ZStack(alignment: .topLeading) {
                // Cable — drawn first so the glyphs sit on top.
                cableShape(
                    chargerCenter: chargerCenter,
                    connectorCenter: connectorCenter
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

                J1772Icon(
                    size: Self.connectorSize,
                    haloColor: tone
                )
                .position(connectorCenter)

                connectorLabel(at: connectorCenter, in: width)
            }
        }
        .frame(height: heroArtworkHeight)
    }

    private var heroArtworkHeight: CGFloat {
        // Tall enough to hold the charger up top and the connector
        // down-right with a sensible cable run between them.
        Self.chargerSize + Self.connectorSize + Spacing.lg + Spacing.lg
    }

    /// Squared cable: out the bottom of the charger, down a bit, 90°
    /// turn toward the connector's column, then 90° turn up to the
    /// connector's top edge.
    private func cableShape(
        chargerCenter: CGPoint,
        connectorCenter: CGPoint
    ) -> Path {
        var p = Path()
        let chargerBottom = CGPoint(
            x: chargerCenter.x,
            y: chargerCenter.y + Self.chargerSize / 2
        )
        let connectorTop = CGPoint(
            x: connectorCenter.x,
            y: connectorCenter.y - Self.connectorSize / 2
        )
        // Mid-point Y where the horizontal run lives — sits between
        // the charger's bottom and the connector's top so the cable
        // makes its turn cleanly.
        let midY = (chargerBottom.y + connectorTop.y) / 2 + 12

        p.move(to: chargerBottom)
        p.addLine(to: CGPoint(x: chargerBottom.x, y: midY))
        p.addLine(to: CGPoint(x: connectorTop.x, y: midY))
        p.addLine(to: connectorTop)
        return p
    }

    private var cableColor: Color {
        switch status {
        case .charging: return tone.opacity(0.85)
        case .offline:  return ColorPalette.mutedForeground.opacity(0.7)
        default:        return tone.opacity(0.7)
        }
    }

    @ViewBuilder
    private func connectorLabel(at center: CGPoint, in width: CGFloat) -> some View {
        if let descriptor = connectors.first {
            VStack(alignment: .leading, spacing: 2) {
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

    @ViewBuilder
    private var statusLine: some View {
        Text(statusTitle)
            .font(.title3.weight(.semibold))
            .foregroundStyle(tone)
            .accessibilityHidden(true)
    }

    private var statusTitle: String {
        switch heroState {
        case .idle:         return "Idle"
        case .plugged:      return "Plugged in"
        case .charging:     return "Charging"
        case .reserved:     return "Reserved"
        case .outOfService: return isOffline ? "Charger offline" : "Out of service"
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
        var bits: [String] = [statusTitle]
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
