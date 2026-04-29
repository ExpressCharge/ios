//
//  J1772Icon.swift
//  ExpresScan
//
//  Outline of an SAE J1772 connector face. Renders just the
//  silhouette — no surrounding plate or LED bezel — so it sits
//  cleanly on a transparent hero next to the wallbox glyph.
//
//  Outline:
//   * Round body (the contact disk) with a small rectangular
//     release-latch tab on top.
//   * Five contact holes inside in the canonical J1772 layout:
//       ─ top pair: L1 (left), L2 (right)
//       ─ middle pair: CP (left), Proximity Detect (right)
//       ─ bottom centre: PE / ground
//
//  Drawn in a neutral foreground colour (no accent tint) so the
//  charger glyph is the single status-bearing element.
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
                style: StrokeStyle(lineWidth: 4, lineJoin: .round)
            )

            // Five contact holes — stroked rather than filled so the
            // whole glyph reads as a wireframe, matching the body
            // outline weight.
            let pinLarge: CGFloat = 6.5
            let pinSmall: CGFloat = 5
            let stroke = StrokeStyle(lineWidth: 3)
            let circle: (CGFloat, CGFloat, CGFloat) -> Path = { x, y, r in
                Path(ellipseIn: CGRect(
                    x: x - r, y: y - r,
                    width: r * 2, height: r * 2
                ))
            }
            // Top pair (L1, L2)
            ctx.stroke(circle(40, 50, pinLarge), with: .color(strokeColor), style: stroke)
            ctx.stroke(circle(60, 50, pinLarge), with: .color(strokeColor), style: stroke)
            // Middle pair (CP, PD)
            ctx.stroke(circle(40, 65, pinSmall), with: .color(strokeColor), style: stroke)
            ctx.stroke(circle(60, 65, pinSmall), with: .color(strokeColor), style: stroke)
            // Bottom (PE)
            ctx.stroke(circle(50, 78, pinLarge), with: .color(strokeColor), style: stroke)
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
        // tangent lines meet the circle.
        let latchHalfWidth: CGFloat = 9
        let latchTop: CGFloat = 14
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
}
#endif
