//
//  ChargerFormFactorIcon.swift
//  ExpresScan
//
//  SwiftUI translation of `expressync/components/brand/chargers/`'s
//  WallboxIcon — rounded-square body, inset LED halo, dark recessed
//  central panel. The halo carries the charger's status colour so the
//  list row can encode online/charging/reserved/offline at a glance,
//  matching the web admin's `ChargerCard` icon halo treatment.
//
//  All five form-factor variants currently render the same Wallbox
//  silhouette — the web has dedicated SVGs for Pulsar / Commander /
//  Wall-mount, but the iOS list never sees more than five distinct
//  shapes today and a single recognisable family glyph keeps the row
//  visually calm. Per-form-factor SVG translations can land in a
//  follow-up if needed.
//

import SwiftUI

struct ChargerFormFactorIcon: View {

    /// Pixel side-length. Defaults match the web SIZE_MAP `md = 48`.
    let size: CGFloat
    /// Status-bearing halo colour. Defaults to the Pulsar Plus teal.
    let haloColor: Color
    /// Optional soft outer-bleed colour rendered as a blurred halo
    /// behind the body — used by `ChargerHero` to make the charging
    /// state pop. Pass `nil` for the standard list-row treatment.
    let glow: Color?

    init(size: CGFloat = 48, haloColor: Color = .teal, glow: Color? = nil) {
        self.size = size
        self.haloColor = haloColor
        self.glow = glow
    }

    var body: some View {
        // Use a 100×100 logical viewBox so the SVG-derived constants
        // translate one-to-one into the SwiftUI shape coordinates.
        Canvas(rendersAsynchronously: false) { ctx, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 100.0
            ctx.scaleBy(x: scale, y: scale)

            // Outer body — rounded square, dark grey.
            let body = Path(roundedRect: CGRect(x: 8, y: 8, width: 84, height: 84),
                            cornerRadius: 19)
            ctx.fill(body, with: .color(Self.bodyColor))

            // Subtle highlight stroke for dimension.
            let highlight = Path(roundedRect: CGRect(x: 9, y: 9, width: 82, height: 82),
                                 cornerRadius: 18)
            ctx.stroke(highlight, with: .color(Self.bodyHighlight),
                       lineWidth: 0.6)

            // Halo outer diffuse glow (LED bleed) — drawn first so the
            // crisp ring sits on top.
            let haloOuter = Path(roundedRect: CGRect(x: 18, y: 18, width: 64, height: 64),
                                 cornerRadius: 14)
            ctx.stroke(
                haloOuter,
                with: .color(haloColor.opacity(0.4)),
                lineWidth: 2
            )

            // Halo ring — the status-bearing LED.
            let halo = Path(roundedRect: CGRect(x: 19, y: 19, width: 62, height: 62),
                            cornerRadius: 13)
            ctx.stroke(
                halo,
                with: .color(haloColor.opacity(0.95)),
                lineWidth: 5
            )

            // Central recessed face.
            let face = Path(roundedRect: CGRect(x: 24, y: 24, width: 52, height: 52),
                            cornerRadius: 10)
            ctx.fill(face, with: .color(Self.faceColor))
        }
        .frame(width: size, height: size)
        .background(glowHalo)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glowHalo: some View {
        if let glow {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(glow.opacity(0.55))
                .blur(radius: size * 0.18)
                .scaleEffect(1.18)
                .accessibilityHidden(true)
        }
    }

    // Approximations of the web's oklch values picked by eye against
    // the rendered SVG; lock to fixed RGB so the icon renders the same
    // in light/dark and doesn't compete with `ColorPalette.background`.
    private static let bodyColor      = Color(red: 0.20, green: 0.21, blue: 0.24)
    private static let bodyHighlight  = Color(red: 0.36, green: 0.37, blue: 0.40)
    private static let faceColor      = Color(red: 0.10, green: 0.11, blue: 0.13)
}

#if DEBUG
#Preview("Halo states") {
    HStack(spacing: 16) {
        ChargerFormFactorIcon(size: 56, haloColor: .green)   // charging
        ChargerFormFactorIcon(size: 56, haloColor: .cyan)    // available
        ChargerFormFactorIcon(size: 56, haloColor: .orange)  // reserved
        ChargerFormFactorIcon(size: 56, haloColor: .red)     // offline / faulted
    }
    .padding()
    .background(Color.black)
}
#endif
