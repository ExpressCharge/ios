//
//  AnimatedNFCGlyph.swift
//  ExpresScan
//
//  The 96 pt NFC waves icon shown on the home screen ("Ready to Scan")
//  and during an active scan. Pulses outward by default; the active-scan
//  primer re-uses this with the `.success` tone to signal "scan a card
//  now".
//
//  iOS 26 native: animation uses `SymbolEffect.variableColor.iterative`
//  on the SF Symbol (gives us a hardware-accelerated breathing rhythm
//  the system also drives for glyphs like `wifi.exclamationmark`). The
//  outer halo is a soft shadow rather than a hand-rolled circle —
//  cheaper on the GPU and matches the web's `.glow-cyan` /
//  `.glow-green` utilities (`expressync/assets/styles.css`).
//
//  Honors `accessibilityReduceMotion`: drops the symbol effect, the
//  glow stays static.
//
//  Spec: `50-ios.md` § "UX details" → "Ready home" / "Scan request".
//

import SwiftUI

public struct AnimatedNFCGlyph: View {

    public let size: CGFloat
    public let tone: StatusPill.Tone

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        size: CGFloat = 96,
        tone: StatusPill.Tone = .info
    ) {
        self.size = size
        self.tone = tone
    }

    public var body: some View {
        let tint = tone.publicFillColor
        Image(systemName: "wave.3.right.circle.fill")
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
            .shadow(color: tint.opacity(0.40), radius: 16)
            .accessibilityLabel("NFC reader ready")
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 24) {
        AnimatedNFCGlyph(size: 96, tone: .info)
        AnimatedNFCGlyph(size: 96, tone: .positive)
    }
    .padding()
}
#endif
