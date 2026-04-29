//
//  J1772Icon.swift
//  ExpresScan
//
//  SwiftUI rendering of an SAE J1772 connector silhouette. The icon
//  shares the same chrome as `ChargerFormFactorIcon` (rounded-square
//  plate with an inset status halo + recessed face) so the charger
//  and connector visually rhyme in `ChargerHero`.
//
//  The J1772 silhouette inside the face plate consists of:
//    * a round contact disk (the body),
//    * a small rectangular locking tab on top,
//    * a short tail flowing into the cable.
//

import SwiftUI

struct J1772Icon: View {

    /// Pixel side-length.
    let size: CGFloat
    /// Status-bearing halo colour.
    let haloColor: Color

    init(size: CGFloat = 56, haloColor: Color = .teal) {
        self.size = size
        self.haloColor = haloColor
    }

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 100.0
            ctx.scaleBy(x: scale, y: scale)

            // Outer body — rounded square.
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

            // Recessed face.
            let face = Path(roundedRect: CGRect(x: 24, y: 24, width: 52, height: 52),
                            cornerRadius: 10)
            ctx.fill(face, with: .color(Self.faceColor))

            // J1772 silhouette — drawn on top of the face. Coordinates
            // are tuned so the connector reads at small sizes.
            let glyph = Self.j1772Path()
            ctx.fill(glyph, with: .color(haloColor.opacity(0.92)))

            // Five recessed contact pins on the disk so the connector is
            // recognisable at hero sizes (24/24/24 across, plus two on
            // the bottom). Tiny — they vanish below ~32pt without
            // muddying the silhouette at hero sizes.
            let pin: (CGFloat, CGFloat) -> Path = { x, y in
                Path(ellipseIn: CGRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2))
            }
            ctx.fill(pin(43, 47), with: .color(Self.faceColor))
            ctx.fill(pin(50, 47), with: .color(Self.faceColor))
            ctx.fill(pin(57, 47), with: .color(Self.faceColor))
            ctx.fill(pin(46, 56), with: .color(Self.faceColor))
            ctx.fill(pin(54, 56), with: .color(Self.faceColor))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Canonical J1772 silhouette inside a 100×100 viewBox. The disk is
    /// centered around (50, 52); the locking tab pokes up from the top.
    private static func j1772Path() -> Path {
        var p = Path()
        // Locking tab.
        p.addRoundedRect(in: CGRect(x: 45, y: 32, width: 10, height: 7),
                         cornerSize: CGSize(width: 1.5, height: 1.5))
        // Circular contact disk.
        p.addEllipse(in: CGRect(x: 36, y: 39, width: 28, height: 28))
        // Short tail flowing into the cable.
        p.addRoundedRect(in: CGRect(x: 47, y: 65, width: 6, height: 6),
                         cornerSize: CGSize(width: 1.5, height: 1.5))
        return p
    }

    private static let bodyColor      = Color(red: 0.20, green: 0.21, blue: 0.24)
    private static let bodyHighlight  = Color(red: 0.36, green: 0.37, blue: 0.40)
    private static let faceColor      = Color(red: 0.10, green: 0.11, blue: 0.13)
}

#if DEBUG
#Preview("J1772 states") {
    HStack(spacing: 16) {
        J1772Icon(size: 56, haloColor: .green)
        J1772Icon(size: 56, haloColor: .cyan)
        J1772Icon(size: 56, haloColor: .orange)
        J1772Icon(size: 56, haloColor: .red)
    }
    .padding()
    .background(Color.black)
}
#endif
