//
//  ChargerHero.swift
//  ExpresScan
//
//  Customer-facing hero for the charger detail screen. Composes the
//  Wallbox glyph with one or more connector glyphs, drawing a curved
//  cable between them and showing each connector's type + max-kW.
//
//  Mirrors the Figma direction (`J7H1XfKeTfnaqPF1nFF1fx`) while
//  reusing the iOS design system: status colour comes from
//  `ChargerStatusVisuals` (so the list and detail never drift), and
//  the surface is the same iOS-26 glass-tint hero used elsewhere.
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
    /// element; the connector(s) sit smaller and to the right.
    private static let chargerSize: CGFloat = 128
    private static let connectorSize: CGFloat = 56

    var body: some View {
        VStack(spacing: Spacing.md) {
            artwork
            statusLine
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .padding(.horizontal, Spacing.base)
        .background(heroBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var heroBackground: some View {
        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .glassEffect(.regular.tint(tone.opacity(0.15)))
    }

    /// The charger + cable + connector composition. We use a relative
    /// `GeometryReader` layout so connector placement scales with
    /// Dynamic Type without absolute pixel coordinates leaking out.
    private var artwork: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let chargerOrigin = CGPoint(
                x: width * 0.18,
                y: height * 0.5
            )
            let connectorRow = connectors.enumerated().map { index, connector in
                ConnectorPlacement(
                    descriptor: connector,
                    center: connectorCenter(
                        index: index,
                        count: connectors.count,
                        width: width,
                        height: height
                    )
                )
            }

            ZStack(alignment: .topLeading) {
                // Cables drawn first so the glyphs sit on top.
                Canvas { ctx, _ in
                    for placement in connectorRow {
                        let cable = cablePath(
                            from: chargerOrigin,
                            to: placement.center
                        )
                        ctx.stroke(
                            cable,
                            with: .color(cableColor),
                            style: StrokeStyle(
                                lineWidth: 3,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    }
                }

                ChargerFormFactorIcon(
                    size: Self.chargerSize,
                    haloColor: tone,
                    glow: glow.opacity(0.55)
                )
                .position(chargerOrigin)

                ForEach(Array(connectorRow.enumerated()), id: \.offset) { _, placement in
                    connectorTile(placement: placement, width: width)
                }
            }
        }
        .frame(height: heroArtworkHeight)
    }

    private var heroArtworkHeight: CGFloat {
        let perConnector: CGFloat = Self.connectorSize + Spacing.sm
        let needed = max(Self.chargerSize, perConnector * CGFloat(max(connectors.count, 1)))
        return needed + Spacing.lg
    }

    private func connectorCenter(
        index: Int,
        count: Int,
        width: CGFloat,
        height: CGFloat
    ) -> CGPoint {
        let column = width * 0.62
        guard count > 1 else {
            return CGPoint(x: column, y: height * 0.32)
        }
        let bandTop = height * 0.18
        let bandBottom = height * 0.82
        let step = (bandBottom - bandTop) / CGFloat(count - 1)
        return CGPoint(x: column, y: bandTop + step * CGFloat(index))
    }

    @ViewBuilder
    private func connectorTile(
        placement: ConnectorPlacement,
        width: CGFloat
    ) -> some View {
        HStack(spacing: Spacing.md) {
            J1772Icon(size: Self.connectorSize, haloColor: tone)
            VStack(alignment: .leading, spacing: 2) {
                Text(kWLabel(for: placement.descriptor))
                    .font(.callout.weight(.semibold))
                Text(typeLabel(for: placement.descriptor))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .position(
            x: placement.center.x + (width - placement.center.x) / 2 - Spacing.sm,
            y: placement.center.y
        )
    }

    private func cablePath(from a: CGPoint, to b: CGPoint) -> Path {
        var p = Path()
        // Pull the start to the right edge of the charger plate and
        // the end to the left edge of the connector plate so the
        // cable doesn't overlap the glyphs.
        let start = CGPoint(x: a.x + Self.chargerSize * 0.32, y: a.y)
        let end = CGPoint(x: b.x - Self.connectorSize * 0.42, y: b.y)
        let mid1 = CGPoint(x: (start.x + end.x) / 2, y: start.y + 18)
        let mid2 = CGPoint(x: (start.x + end.x) / 2, y: end.y + 18)
        p.move(to: start)
        p.addCurve(to: end, control1: mid1, control2: mid2)
        return p
    }

    private var cableColor: Color {
        switch status {
        case .charging: return tone.opacity(0.55)
        case .offline:  return ColorPalette.borderSubtle.opacity(0.5)
        default:        return ColorPalette.borderSubtle.opacity(0.85)
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

    private struct ConnectorPlacement {
        let descriptor: ChargerDetailViewModel.ConnectorDescriptor
        let center: CGPoint
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
