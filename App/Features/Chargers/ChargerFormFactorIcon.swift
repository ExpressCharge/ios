//
//  ChargerFormFactorIcon.swift
//  ExpresScan
//
//  SwiftUI translation of `expresscharge/components/brand/chargers/`'s
//  charger family glyphs. All variants share the same dark housing
//  + subtle highlight + recessed-panel material language so the list
//  row reads as one family; the status-bearing element differs per
//  form factor:
//
//   * .wallbox / .pulsar / .commander / .wallMount — rounded-square
//     body with an inset rounded-rect LED halo and recessed
//     rectangular face. The default for branded wall-mounted units.
//   * .generic — same body silhouette as wallbox, but with a circular
//     LED halo around a circular recessed port. Reads as "some kind
//     of charger" without picking a brand-specific shape.
//   * .tesla — tall narrow rounded rectangle (Tesla Wall Connector
//     Gen 3 proportions) with a recessed front panel and a vertical
//     LED light strip down the centre as the status indicator,
//     mirroring the real device's faceplate light strip.
//
//  Halo / strip colour carries the charger's status (idle / charging
//  / reserved / offline), keeping `ChargerStatusVisuals` as the
//  single source of truth.
//

import SwiftUI

struct ChargerFormFactorIcon: View {

    /// Pixel side-length. Defaults match the web SIZE_MAP `md = 48`.
    let size: CGFloat
    /// Form factor selects which silhouette + status-indicator
    /// treatment to render.
    let formFactor: ChargerListEntry.FormFactor
    /// Status-bearing halo / strip colour. Defaults to the Pulsar
    /// Plus teal.
    let haloColor: Color
    /// Optional soft outer-bleed colour rendered as a blurred halo
    /// behind the body — used by `ChargerHero` to make the charging
    /// state pop. Pass `nil` for the standard list-row treatment.
    let glow: Color?

    init(
        size: CGFloat = 48,
        formFactor: ChargerListEntry.FormFactor = .wallbox,
        haloColor: Color = .teal,
        glow: Color? = nil
    ) {
        self.size = size
        self.formFactor = formFactor
        self.haloColor = haloColor
        self.glow = glow
    }

    var body: some View {
        // Use a 100×100 logical viewBox so the SVG-derived constants
        // translate one-to-one into the SwiftUI shape coordinates.
        Canvas(rendersAsynchronously: false) { ctx, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 100.0
            ctx.scaleBy(x: scale, y: scale)

            switch formFactor {
            case .tesla:
                drawTesla(into: &ctx)
            case .generic:
                drawGeneric(into: &ctx)
            case .wallbox, .pulsar, .commander, .wallMount:
                drawWallbox(into: &ctx)
            }
        }
        .frame(width: size, height: size)
        .background(glowHalo)
        .accessibilityHidden(true)
    }

    // MARK: - Wallbox-family (default)

    private func drawWallbox(into ctx: inout GraphicsContext) {
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

    // MARK: - Generic charger

    /// Same outer body as the wallbox so the family reads as one,
    /// but the LED halo + recessed face are circular — reads as a
    /// generic round-port charger station.
    private func drawGeneric(into ctx: inout GraphicsContext) {
        let body = Path(roundedRect: CGRect(x: 8, y: 8, width: 84, height: 84),
                        cornerRadius: 19)
        ctx.fill(body, with: .color(Self.bodyColor))

        let highlight = Path(roundedRect: CGRect(x: 9, y: 9, width: 82, height: 82),
                             cornerRadius: 18)
        ctx.stroke(highlight, with: .color(Self.bodyHighlight), lineWidth: 0.6)

        let haloOuter = Path(ellipseIn: CGRect(x: 18, y: 18, width: 64, height: 64))
        ctx.stroke(haloOuter, with: .color(haloColor.opacity(0.4)), lineWidth: 2)

        let halo = Path(ellipseIn: CGRect(x: 20, y: 20, width: 60, height: 60))
        ctx.stroke(halo, with: .color(haloColor.opacity(0.95)), lineWidth: 5)

        let face = Path(ellipseIn: CGRect(x: 26, y: 26, width: 48, height: 48))
        ctx.fill(face, with: .color(Self.faceColor))
    }

    // MARK: - Tesla Wall Connector

    /// Tall narrow rounded rect echoing the Tesla Wall Connector Gen
    /// 3's faceplate proportions (~155mm wide × 345mm tall, ~9:20).
    /// Status is carried by the vertical LED light strip down the
    /// centre of the recessed front panel — the same affordance the
    /// real device uses.
    private func drawTesla(into ctx: inout GraphicsContext) {
        // Outer body — tall rounded rectangle.
        let body = Path(roundedRect: CGRect(x: 32, y: 6, width: 36, height: 88),
                        cornerRadius: 14)
        ctx.fill(body, with: .color(Self.bodyColor))

        let highlight = Path(roundedRect: CGRect(x: 33, y: 7, width: 34, height: 86),
                             cornerRadius: 13)
        ctx.stroke(highlight, with: .color(Self.bodyHighlight), lineWidth: 0.6)

        // Recessed front panel — abstracts the Gen 3's tempered
        // glass faceplate.
        let face = Path(roundedRect: CGRect(x: 37, y: 12, width: 26, height: 76),
                        cornerRadius: 9)
        ctx.fill(face, with: .color(Self.faceColor))

        // Vertical LED light strip — outer diffuse bleed under crisp
        // strip, mirroring the wallbox halo's two-layer treatment.
        let stripOuter = Path(
            roundedRect: CGRect(x: 45.5, y: 21, width: 9, height: 58),
            cornerRadius: 4.5
        )
        ctx.fill(stripOuter, with: .color(haloColor.opacity(0.4)))

        let strip = Path(
            roundedRect: CGRect(x: 47, y: 23, width: 6, height: 54),
            cornerRadius: 3
        )
        ctx.fill(strip, with: .color(haloColor.opacity(0.95)))
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
#Preview("Halo states (wallbox)") {
    HStack(spacing: 16) {
        ChargerFormFactorIcon(size: 56, haloColor: .green)   // charging
        ChargerFormFactorIcon(size: 56, haloColor: .cyan)    // available
        ChargerFormFactorIcon(size: 56, haloColor: .orange)  // reserved
        ChargerFormFactorIcon(size: 56, haloColor: .red)     // offline / faulted
    }
    .padding()
    .background(Color.black)
}

#Preview("Form factors") {
    HStack(spacing: 24) {
        VStack(spacing: 8) {
            ChargerFormFactorIcon(size: 88, formFactor: .wallbox, haloColor: .cyan)
            Text("Wallbox").font(.caption).foregroundStyle(.white)
        }
        VStack(spacing: 8) {
            ChargerFormFactorIcon(size: 88, formFactor: .generic, haloColor: .cyan)
            Text("Generic").font(.caption).foregroundStyle(.white)
        }
        VStack(spacing: 8) {
            ChargerFormFactorIcon(size: 88, formFactor: .tesla, haloColor: .green)
            Text("Tesla").font(.caption).foregroundStyle(.white)
        }
    }
    .padding()
    .background(Color.black)
}
#endif
