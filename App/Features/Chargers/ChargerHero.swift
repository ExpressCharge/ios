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
    let formFactor: ChargerListEntry.FormFactor

    private var status: ChargerStatusVisuals.Status {
        ChargerStatusVisuals.status(for: heroState, isOffline: isOffline)
    }

    private var tone: Color { ChargerStatusVisuals.tone(for: status) }
    private var glow: Color { ChargerStatusVisuals.glow(for: status) }

    /// Hero artwork sizing.
    private static let chargerSize: CGFloat = 132
    private static let connectorSize: CGFloat = 96
    private static let cableLineWidth: CGFloat = 8
    private static let cableHighlightLineWidth: CGFloat = 3
    private static let cableHighlightOpacity: Double = 0.22
    private static let cableBendRadius: CGFloat = 14
    private static let chargerBootSize = CGSize(width: 18, height: 10)
    private static let connectorBootSize = CGSize(width: 14, height: 8)
    private static let bootCornerRadius: CGFloat = 3

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

            let chargerBottom = CGPoint(
                x: chargerCenter.x,
                y: chargerCenter.y + Self.chargerSize / 2
            )
            let connectorBottom = CGPoint(
                x: connectorCenter.x,
                y: connectorCenter.y + Self.connectorSize / 2 - 4
            )

            ZStack(alignment: .topLeading) {
                let cable = cableShape(
                    chargerBottom: chargerBottom,
                    connectorBottom: connectorBottom
                )

                cable.stroke(
                    cableColor,
                    style: StrokeStyle(
                        lineWidth: Self.cableLineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                cable.stroke(
                    Color.white.opacity(Self.cableHighlightOpacity),
                    style: StrokeStyle(
                        lineWidth: Self.cableHighlightLineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                // Strain-relief boots ("lug nuts" in the design
                // brief). Track I2 fix: previously the boots floated
                // a few points below the charger / connector with a
                // visible gap and inherited the cable's translucent
                // colour, making them read as detached. We now
                // position them so they overlap the charger body's
                // bottom edge, and `strainReliefBoot` fills with the
                // status tone at full opacity so the boot reads as
                // a solid grommet attached to the device.
                strainReliefBoot(size: Self.chargerBootSize)
                    .position(
                        x: chargerBottom.x,
                        y: chargerBottom.y - 2
                    )

                strainReliefBoot(size: Self.connectorBootSize)
                    .position(
                        x: connectorBottom.x,
                        y: connectorBottom.y - 2
                    )

                ChargerFormFactorIcon(
                    size: Self.chargerSize,
                    formFactor: formFactor,
                    haloColor: tone,
                    glow: glow.opacity(0.45)
                )
                .position(chargerCenter)

                connectorGlyph
                    .position(connectorCenter)

                connectorMeta(at: connectorCenter)
            }
        }
        .frame(height: heroArtworkHeight)
    }

    /// Connector silhouette chosen from the first descriptor's
    /// `connectorType`. NACS renders as a smooth circle; everything
    /// else (including unknown / nil) falls back to the J1772
    /// silhouette since J1772 is the most common physical connector
    /// in the fleet today.
    @ViewBuilder
    private var connectorGlyph: some View {
        switch connectors.first?.connectorType {
        case .nacs:
            NACSIcon(size: Self.connectorSize)
        default:
            J1772Icon(size: Self.connectorSize)
        }
    }

    private var heroArtworkHeight: CGFloat {
        // Tall enough to hold the charger + connector at one
        // vertical centre plus the cable U beneath them, plus the
        // headroom needed by the kW/connector meta block which
        // (Track I2) now sits above the connector glyph.
        Self.chargerSize + Self.connectorSize / 2 + Spacing.xl + Spacing.xl
    }

    /// Squared cable with filleted bend corners: out the bottom of
    /// the charger, down to the run, gentle 90° fillet toward the
    /// connector, gentle 90° fillet up to the connector's bottom
    /// edge. `addArc(tangent1End:tangent2End:radius:)` keeps the
    /// straight legs straight and only rounds the corner geometry.
    private func cableShape(
        chargerBottom: CGPoint,
        connectorBottom: CGPoint
    ) -> Path {
        // Run the horizontal segment beneath both glyphs so the
        // turns sit clear of the artwork.
        let runY = max(chargerBottom.y, connectorBottom.y) + Spacing.lg
        let chargerCorner = CGPoint(x: chargerBottom.x, y: runY)
        let connectorCorner = CGPoint(x: connectorBottom.x, y: runY)
        let radius = Self.cableBendRadius

        var p = Path()
        p.move(to: chargerBottom)
        p.addArc(
            tangent1End: chargerCorner,
            tangent2End: connectorCorner,
            radius: radius
        )
        p.addArc(
            tangent1End: connectorCorner,
            tangent2End: connectorBottom,
            radius: radius
        )
        p.addLine(to: connectorBottom)
        return p
    }

    /// Strain-relief boot rendered at each cable terminus — a small
    /// filled rounded rect that reads as a solid grommet where the
    /// cable enters each device. Filled with `bootColor` (no opacity
    /// — distinct from `cableColor` which carries 0.7-0.85) so the
    /// boot remains readable when overlapped with the charger body.
    private func strainReliefBoot(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: Self.bootCornerRadius, style: .continuous)
            .fill(bootColor)
            .frame(width: size.width, height: size.height)
    }

    /// Fully-opaque variant of the cable colour. Mirrors the
    /// charging / offline / idle distinctions but at 1.0 alpha so
    /// the boot reads as a solid grommet rather than a translucent
    /// dot floating off the device.
    private var bootColor: Color {
        switch status {
        case .offline: return ColorPalette.mutedForeground
        default: return tone
        }
    }

    private var cableColor: Color {
        switch status {
        case .charging: return tone.opacity(0.85)
        case .offline: return ColorPalette.mutedForeground.opacity(0.7)
        default: return tone.opacity(0.7)
        }
    }

    /// kW + connector type label, centred above the connector
    /// glyph so it reads as the spec sheet hovering directly over
    /// the part it describes. Track I2 moved this from the left of
    /// the glyph (where it visually competed with the cable) to
    /// straight above.
    @ViewBuilder
    private func connectorMeta(at center: CGPoint) -> some View {
        if let descriptor = connectors.first {
            VStack(alignment: .center, spacing: 2) {
                Text(kWLabel(for: descriptor))
                    .font(.headline)
                Text(typeLabel(for: descriptor))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .position(
                x: center.x,
                y: center.y - Self.connectorSize / 2 - 18
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
        case .idle: return "Idle"
        case .plugged: return "Plugged in"
        case .charging: return "Charging"
        case .reserved: return "Reserved"
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
