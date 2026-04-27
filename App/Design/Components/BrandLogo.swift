//
//  BrandLogo.swift
//  ExpresScan
//
//  Squircle-with-Zap brand mark mirroring the web `ExpresSyncLogo`
//  component (`expressync/components/brand/ExpresSyncBrand.tsx`
//  lines 49–107). On iOS 26 we render:
//
//   - A continuous-curvature `RoundedRectangle` (corner radius 30 % of
//     the side length, matching the web's `rounded-[30%]`).
//   - A linear gradient fill cycling cyan → green → violet → cyan
//     whose endpoints flow on an 8 s loop driven by `TimelineView`.
//   - A white thunderbolt SF Symbol with `.symbolEffect(.pulse)` so it
//     pulses gently — the iOS-native equivalent of the web's
//     BorderBeam.
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

        var iconDimension: CGFloat { dimension * 0.55 }
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
        .accessibilityLabel("ExpresScan")
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
                Image(systemName: "bolt.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: size.iconDimension,
                        height: size.iconDimension
                    )
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, isActive: !reduceMotion)
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
