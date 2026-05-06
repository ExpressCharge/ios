//
//  NACSIcon.swift
//  ExpresScan
//
//  NACS / Tesla connector face — drawn in the same recessed-halo
//  language as `J1772Icon`. NACS is essentially a J1772 silhouette
//  without the rectangular release-latch tab (the connector face is
//  a smooth circle), so this view is a circle silhouette with the
//  same neutral inner LED ring inside.
//
//  Layers (outer → inner):
//   * Body silhouette stroke — single circle, no latch tab.
//   * Inner halo ring concentric inside the body: soft outer diffuse
//     bleed under a crisp ring. Drawn in the muted neutral so the
//     wallbox glyph remains the single status-bearing element of
//     the hero.
//
//  The body shares J1772's centre and radius so the connector sits
//  at the same vertical position relative to the cable, keeping the
//  hero composition consistent across connector types.
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

            // Body — plain circle (no latch tab). Centre matches
            // J1772 so the cable connects at the same y.
            let bodyCenter = CGPoint(x: 50, y: 60)
            let bodyRadius: CGFloat = 32
            let body = Path(ellipseIn: CGRect(
                x: bodyCenter.x - bodyRadius,
                y: bodyCenter.y - bodyRadius,
                width: bodyRadius * 2,
                height: bodyRadius * 2
            ))
            ctx.stroke(
                body,
                with: .color(strokeColor),
                style: StrokeStyle(lineWidth: 3, lineJoin: .round)
            )

            // Inner halo ring — same opacity / weight pair as the
            // wallbox and J1772 LED ring so the family reads as one.
            let halo = ColorPalette.mutedForeground
            let haloOuter = Path(ellipseIn: CGRect(
                x: bodyCenter.x - 26, y: bodyCenter.y - 26,
                width: 52, height: 52
            ))
            ctx.stroke(haloOuter, with: .color(halo.opacity(0.4)), lineWidth: 2)

            let haloRing = Path(ellipseIn: CGRect(
                x: bodyCenter.x - 25, y: bodyCenter.y - 25,
                width: 50, height: 50
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
