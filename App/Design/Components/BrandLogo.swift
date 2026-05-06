//
//  BrandLogo.swift
//  ExpresScan
//
//  Squircle-with-Zap brand mark mirroring the web `ExpresSyncLogo`
//  component (`expresscharge/components/brand/ExpresSyncBrand.tsx`
//  lines 49–107). On iOS 26 we render:
//
//   - A continuous-curvature `RoundedRectangle` (corner radius 30 % of
//     the side length, matching the web's `rounded-[30%]`).
//   - A linear gradient fill cycling cyan → green → cyan whose endpoints
//     flow on an 8 s loop driven by `TimelineView`.
//   - A white Lucide Zap glyph (custom `ZapShape`) — the SAME path the
//     app icon uses (`expresscharge/static/logo-app.svg`) — filled white
//     and outlined with a matching rounded-join stroke so the corners
//     are softened identically.
//   - A soft outer glow built from a second copy of the squircle at
//     `.scaleEffect(1.15)` / `.opacity(0.35)` / `.blur(radius: 8)`,
//     mirroring the `blur-md animate-pulse` halo at line 104 of the
//     web component.
//
//  Honors `accessibilityReduceMotion`: drops the symbol pulse and the
//  gradient flow; the static gradient and outer glow stay.
//

import SwiftUI

public struct BrandLogo: View {

    public enum Size: Sendable {
        case small   // 32 pt — sidebar / header
        case medium  // 40 pt — login banner companion
        case large   // 96 pt — splash hero

        var dimension: CGFloat {
            switch self {
            case .small:  return 32
            case .medium: return 40
            case .large:  return 96
            }
        }

        // Sized so the visible Zap path matches the app icon's bolt
        // proportions: SVG bolt occupies 18/24 of its 0.45-of-canvas
        // bounding box, i.e. 33.75 % of the canvas wide. Reverse-solving:
        // visible-width = iconDimension * 18/24 = 0.34 → iconDimension
        // ≈ 0.45 × dimension. This bumps the bolt to feel as prominent
        // on the splash screen as it does on the home-screen icon.
        var iconDimension: CGFloat { dimension * 0.56 }
        var cornerRadius: CGFloat { dimension * 0.30 }
        var glowBlur: CGFloat { dimension * 0.10 }
    }

    public let size: Size

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(size: Size = .medium) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            outerGlow
            squircle
        }
        .frame(width: size.dimension * 1.30, height: size.dimension * 1.30)
        .accessibilityElement()
        .accessibilityLabel("ExpressCharge")
    }

    // MARK: - Layers

    @ViewBuilder
    private var squircle: some View {
        if reduceMotion {
            squircleShape(gradient: staticGradient)
        } else {
            TimelineView(.animation) { context in
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 8) / 8
                squircleShape(
                    gradient: animatedGradient(phase: phase)
                )
            }
        }
    }

    private func squircleShape(gradient: LinearGradient) -> some View {
        RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
            .fill(gradient)
            .frame(width: size.dimension, height: size.dimension)
            .overlay(
                ZapShape()
                    .fill(.white)
                    .overlay(
                        ZapShape().stroke(
                            .white,
                            style: StrokeStyle(
                                lineWidth: size.iconDimension / 24 * 2,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    )
                    .frame(
                        width: size.iconDimension,
                        height: size.iconDimension
                    )
                    .shadow(color: .white.opacity(0.5), radius: 4)
            )
    }

    private var outerGlow: some View {
        RoundedRectangle(cornerRadius: size.cornerRadius * 1.15, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [ColorPalette.glowCyan, ColorPalette.glowGreen],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(
                width: size.dimension * 1.15,
                height: size.dimension * 1.15
            )
            .opacity(0.35)
            .blur(radius: size.glowBlur)
    }

    // MARK: - Gradient

    private var brandColors: [Color] {
        // Cyan → green → cyan. The previous violet middle stop read as
        // a darker-blue band that visually clashed with the cyan ends;
        // dropping it leaves a cleaner cyan-green cycle that mirrors the
        // web component's lighter palette.
        [
            ColorPalette.primaryCyan,
            ColorPalette.voltGreen,
            ColorPalette.primaryCyan,
        ]
    }

    private var staticGradient: LinearGradient {
        LinearGradient(
            colors: brandColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func animatedGradient(phase: Double) -> LinearGradient {
        LinearGradient(
            colors: brandColors,
            startPoint: UnitPoint(x: phase, y: 0),
            endPoint: UnitPoint(x: phase + 1, y: 1)
        )
    }
}

// MARK: - Bolt path

/// Lucide Zap thunderbolt — the exact path used by the app icon source
/// (`expresscharge/static/logo-app.svg`). Drawn in a 24×24 viewBox and
/// scaled to fit `rect`.
private struct ZapShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }
        var path = Path()
        path.move(to: p(13, 2))
        path.addLine(to: p(3, 14))
        path.addLine(to: p(12, 14))
        path.addLine(to: p(11, 22))
        path.addLine(to: p(21, 10))
        path.addLine(to: p(12, 10))
        path.closeSubpath()
        return path
    }
}

#if DEBUG
#Preview("BrandLogo sizes") {
    VStack(spacing: 32) {
        BrandLogo(size: .small)
        BrandLogo(size: .medium)
        BrandLogo(size: .large)
    }
    .padding()
}
#endif
