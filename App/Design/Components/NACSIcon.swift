//
//  NACSIcon.swift
//  ExpresScan
//
//  NACS / SAE J3400 (Tesla) connector face. Distinguished from J1772
//  by:
//   * Slightly wider-than-tall outer silhouette (no latch tab, more
//     of a horizontal oval than a perfect circle), and
//   * Two large round pin holes side-by-side in the upper half of
//     the face — these handle DC+/DC− on DC fast charging and
//     L1/L2 on AC. The three smaller pins (CP, PP, G) below are
//     intentionally omitted — at icon size they read as noise.
//
//  Layers (outer → inner):
//   * Body silhouette stroke — slightly squashed ellipse.
//   * Two large filled pin holes in the upper half.
//   * Inner halo ring inside the body, same recessed-halo treatment
//     as `J1772Icon` so the connector family reads consistently.
//
//  Centre matches J1772 so the cable connects at the same y in the
//  hero composition.
//

import SwiftUI

struct NACSIcon: View {

    /// Pixel side-length.
    let size: CGFloat
    /// Stroke colour for the silhouette outline. Defaults to the
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

            let bodyCenter = CGPoint(x: 50, y: 60)
            // Ellipse: slightly wider than tall (~14% wider). This is
            // the visual cue that distinguishes NACS from J1772's
            // perfect circle and reads correctly even at the 24pt
            // list-row size.
            let bodyHalfWidth: CGFloat = 34
            let bodyHalfHeight: CGFloat = 30
            let body = Path(
                ellipseIn: CGRect(
                    x: bodyCenter.x - bodyHalfWidth,
                    y: bodyCenter.y - bodyHalfHeight,
                    width: bodyHalfWidth * 2,
                    height: bodyHalfHeight * 2
                ))
            ctx.stroke(
                body,
                with: .color(strokeColor),
                style: StrokeStyle(lineWidth: 3, lineJoin: .round)
            )

            // Two large pin holes in the upper half of the face. The
            // pins are sized so the gap between them is roughly equal
            // to a single pin's diameter — matches photographic
            // references of the NACS face.
            let pinRadius: CGFloat = 7
            let pinY = bodyCenter.y - 7
            let pinDX: CGFloat = 11
            for dx in [-pinDX, pinDX] {
                let pin = Path(
                    ellipseIn: CGRect(
                        x: bodyCenter.x + dx - pinRadius,
                        y: pinY - pinRadius,
                        width: pinRadius * 2,
                        height: pinRadius * 2
                    ))
                ctx.fill(pin, with: .color(strokeColor))
            }

            // Inner halo ring — same opacity / weight pair as the
            // wallbox and J1772 LED ring so the family reads as one.
            let halo = ColorPalette.mutedForeground
            let haloOuterW: CGFloat = 56
            let haloOuterH: CGFloat = 48
            let haloOuter = Path(
                ellipseIn: CGRect(
                    x: bodyCenter.x - haloOuterW / 2,
                    y: bodyCenter.y - haloOuterH / 2,
                    width: haloOuterW,
                    height: haloOuterH
                ))
            ctx.stroke(haloOuter, with: .color(halo.opacity(0.4)), lineWidth: 2)

            let haloRingW: CGFloat = 54
            let haloRingH: CGFloat = 46
            let haloRing = Path(
                ellipseIn: CGRect(
                    x: bodyCenter.x - haloRingW / 2,
                    y: bodyCenter.y - haloRingH / 2,
                    width: haloRingW,
                    height: haloRingH
                ))
            ctx.stroke(haloRing, with: .color(halo.opacity(0.95)), lineWidth: 4)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 16) {
        NACSIcon(size: 96)
        NACSIcon(size: 96, strokeColor: ColorPalette.primaryCyan)
        NACSIcon(size: 56)
    }
    .padding()
    .background(Color.black)
}
#endif
