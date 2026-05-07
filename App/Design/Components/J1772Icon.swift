//
//  J1772Icon.swift
//  ExpresScan
//
//  SAE J1772 connector face, drawn to feel like a peer of the
//  wallbox glyph (`ChargerFormFactorIcon`). Same recessed-halo
//  language: silhouette outline + concentric inner LED ring.
//
//  Layers (outer → inner):
//   * Body silhouette stroke — round contact disk plus the
//     rectangular release-latch tab on top.
//   * Inner halo ring inside the round body: a soft outer diffuse
//     bleed and a crisp ring on top. Drawn in the muted neutral so
//     the wallbox glyph remains the single status-bearing element
//     of the hero.
//
//  No pin holes, no inner filled face — the halo alone reads as the
//  socket well, keeping the J1772 visually lighter than the wallbox.
//

import SwiftUI

struct J1772Icon: View {

    /// Pixel side-length.
    let size: CGFloat
    /// Stroke colour for the outline + holes. Defaults to the
    /// design system's foreground so the connector reads as a
    /// neutral component, not a status indicator.
    let strokeColor: Color

    init(size: CGFloat = 96, strokeColor: Color = ColorPalette.foreground) {
        self.size = size
        self.strokeColor = strokeColor
    }

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 100.0
            ctx.scaleBy(x: scale, y: scale)

            let body = bodyOutline()
            ctx.stroke(
                body,
                with: .color(strokeColor),
                style: StrokeStyle(lineWidth: 3, lineJoin: .round)
            )

            // Inner halo ring — concentric circle inside the round
            // body. Mirrors the wallbox's two-layer LED treatment
            // (diffuse bleed under a crisp ring) but in the muted
            // neutral so this glyph stays status-agnostic.
            let halo = ColorPalette.mutedForeground
            let bodyCenter = CGPoint(x: 50, y: 60)
            let haloOuter = Path(
                ellipseIn: CGRect(
                    x: bodyCenter.x - 26, y: bodyCenter.y - 26,
                    width: 52, height: 52
                ))
            ctx.stroke(haloOuter, with: .color(halo.opacity(0.4)), lineWidth: 2)

            let haloRing = Path(
                ellipseIn: CGRect(
                    x: bodyCenter.x - 25, y: bodyCenter.y - 25,
                    width: 50, height: 50
                ))
            ctx.stroke(haloRing, with: .color(halo.opacity(0.95)), lineWidth: 4)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Canonical J1772 outline in a 100×100 viewBox: a round body
    /// with a small rectangular release-latch tab joined to the
    /// top. Drawn as a single closed path so the stroke wraps the
    /// silhouette continuously.
    private func bodyOutline() -> Path {
        let bodyCenter = CGPoint(x: 50, y: 60)
        let bodyRadius: CGFloat = 32
        // Latch geometry — sits above the body, joining where the
        // tangent lines meet the circle. Half-width widened from 9 to
        // 11 (Track I2) so the lock reads at smaller charger-list
        // sizes without losing its silhouette.
        let latchHalfWidth: CGFloat = 11
        let latchTop: CGFloat = 13
        // Compute the y-coordinate on the circle where the latch's
        // sides meet (so the joints are tangent).
        let dx = latchHalfWidth
        let dy = sqrt(bodyRadius * bodyRadius - dx * dx)
        let joinY = bodyCenter.y - dy

        var p = Path()
        // Start at the right joint, sweep clockwise around the
        // bottom of the body.
        p.move(to: CGPoint(x: bodyCenter.x + dx, y: joinY))
        p.addArc(
            center: bodyCenter,
            radius: bodyRadius,
            // SwiftUI angles: 0° = right (3 o'clock), grows clockwise.
            startAngle: .radians(atan2(joinY - bodyCenter.y, dx)),
            endAngle: .radians(atan2(joinY - bodyCenter.y, -dx)),
            clockwise: false
        )
        // Up the left side of the latch.
        p.addLine(to: CGPoint(x: bodyCenter.x - dx, y: latchTop))
        // Across the top.
        p.addLine(to: CGPoint(x: bodyCenter.x + dx, y: latchTop))
        // Down the right side back to the join.
        p.addLine(to: CGPoint(x: bodyCenter.x + dx, y: joinY))
        p.closeSubpath()
        return p
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 16) {
        J1772Icon(size: 96)
        J1772Icon(size: 96, strokeColor: ColorPalette.primaryCyan)
        J1772Icon(size: 56)
    }
    .padding()
    .background(Color.black)
}
#endif
