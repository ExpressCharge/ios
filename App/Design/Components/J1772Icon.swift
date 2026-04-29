//
//  J1772Icon.swift
//  ExpresScan
//
//  SwiftUI rendering of the SAE J1772 connector inlet face — the
//  round port with five contact holes that drivers see on the EV
//  side. Wrapped in the same rounded-square chrome as
//  `ChargerFormFactorIcon` so the charger and connector visually
//  rhyme in `ChargerHero`.
//
//  The five-hole layout is canonical for J1772:
//   * Two large pilot/control contacts on top (L1, L2)
//   * Two large power contacts in the middle (CP, CS / N)
//   * One large ground contact at the bottom (PE)
//

import SwiftUI

struct J1772Icon: View {

    /// Pixel side-length.
    let size: CGFloat
    /// Status-bearing halo colour.
    let haloColor: Color

    init(size: CGFloat = 88, haloColor: Color = .teal) {
        self.size = size
        self.haloColor = haloColor
    }

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 100.0
            ctx.scaleBy(x: scale, y: scale)

            // Outer body — rounded square plate.
            let body = Path(roundedRect: CGRect(x: 8, y: 8, width: 84, height: 84),
                            cornerRadius: 19)
            ctx.fill(body, with: .color(Self.bodyColor))

            let highlight = Path(roundedRect: CGRect(x: 9, y: 9, width: 82, height: 82),
                                 cornerRadius: 18)
            ctx.stroke(highlight, with: .color(Self.bodyHighlight), lineWidth: 0.6)

            // Outer halo glow + crisp ring (LED bezel).
            let haloOuter = Path(roundedRect: CGRect(x: 18, y: 18, width: 64, height: 64),
                                 cornerRadius: 14)
            ctx.stroke(haloOuter, with: .color(haloColor.opacity(0.4)), lineWidth: 2)

            let halo = Path(roundedRect: CGRect(x: 19, y: 19, width: 62, height: 62),
                            cornerRadius: 13)
            ctx.stroke(halo, with: .color(haloColor.opacity(0.95)), lineWidth: 5)

            // J1772 connector face — large outer ring.
            let face = Path(ellipseIn: CGRect(x: 26, y: 26, width: 48, height: 48))
            ctx.fill(face, with: .color(Self.faceColor))
            ctx.stroke(face, with: .color(haloColor.opacity(0.95)), lineWidth: 2.5)

            // Five contact holes laid out in the canonical J1772 face.
            // Coordinates are tuned for the 100×100 viewBox; the
            // outer face is centered at (50, 50) with radius 24.
            let pinRadius: CGFloat = 5.6
            let pin: (CGFloat, CGFloat) -> Path = { x, y in
                Path(ellipseIn: CGRect(
                    x: x - pinRadius,
                    y: y - pinRadius,
                    width: pinRadius * 2,
                    height: pinRadius * 2
                ))
            }
            // Top pair (L1, L2) — large power contacts.
            ctx.fill(pin(40, 38), with: .color(Self.holeColor))
            ctx.fill(pin(60, 38), with: .color(Self.holeColor))
            // Middle pair (CP / CS / Neutral) — slightly smaller in
            // real life, here normalised for legibility.
            ctx.fill(pin(38, 52), with: .color(Self.holeColor))
            ctx.fill(pin(62, 52), with: .color(Self.holeColor))
            // Bottom (PE / ground) — single hole.
            ctx.fill(pin(50, 65), with: .color(Self.holeColor))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static let bodyColor      = Color(red: 0.20, green: 0.21, blue: 0.24)
    private static let bodyHighlight  = Color(red: 0.36, green: 0.37, blue: 0.40)
    private static let faceColor      = Color(red: 0.10, green: 0.11, blue: 0.13)
    private static let holeColor      = Color(red: 0.04, green: 0.04, blue: 0.06)
}

#if DEBUG
#Preview("J1772 states") {
    HStack(spacing: 16) {
        J1772Icon(size: 88, haloColor: .green)
        J1772Icon(size: 88, haloColor: .cyan)
        J1772Icon(size: 88, haloColor: .orange)
        J1772Icon(size: 88, haloColor: .red)
    }
    .padding()
    .background(Color.black)
}
#endif
