//
//  AnimatedNFCGlyph.swift
//  ExpresScan
//
//  The 96 pt NFC waves icon shown on the home screen ("Ready to Scan")
//  and during an active scan. Pulses outward on a 0.8 s cycle by
//  default; the active-scan view re-uses this with `cycle = 0.4` to
//  signal "scan a card now".
//
//  Honors `accessibilityReduceMotion` per the wireframes — when the
//  user has it on, we render a static glow instead of the pulse.
//
//  Spec: `50-ios.md` § "UX details" → "Ready home" / "Scan request".
//

import SwiftUI

public struct AnimatedNFCGlyph: View {

    public let size: CGFloat
    public let tint: Color
    /// Pulse cycle in seconds. 0.8 s on idle, 0.4 s when armed.
    public let cycle: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse: CGFloat = 0

    public init(
        size: CGFloat = 96,
        tint: Color = ColorPalette.primaryCyan,
        cycle: Double = 0.8
    ) {
        self.size = size
        self.tint = tint
        self.cycle = cycle
    }

    public var body: some View {
        ZStack {
            // Outer halo. Pulses scale + opacity. Reduce Motion → flat.
            Circle()
                .fill(tint.opacity(reduceMotion ? 0.14 : 0.25 - Double(pulse) * 0.20))
                .frame(width: size * 1.6, height: size * 1.6)
                .scaleEffect(reduceMotion ? 1.0 : 1.0 + pulse * 0.20)

            Image(systemName: "wave.3.right.circle.fill")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .accessibilityLabel("NFC reader ready")
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: cycle).repeatForever(autoreverses: true)
            ) {
                pulse = 1.0
            }
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 24) {
        AnimatedNFCGlyph(size: 96, tint: ColorPalette.primaryCyan, cycle: 0.8)
        AnimatedNFCGlyph(size: 96, tint: ColorPalette.voltGreen, cycle: 0.4)
    }
    .padding()
}
#endif
