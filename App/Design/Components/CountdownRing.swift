//
//  CountdownRing.swift
//  ExpresScan
//
//  Circular progress ring shown during a scan request — depletes from
//  100 % at `expiresAt - issuedAt` down to 0 % at `expiresAt`. Driven
//  by the wall clock so the ring stays accurate even if the app was
//  briefly suspended.
//
//  Spec: `50-ios.md` § "UX details" → "Scan request".
//

import SwiftUI

public struct CountdownRing: View {

    /// 0 = empty, 1 = full. Clamped on read.
    public let progress: Double
    public let lineWidth: CGFloat
    public let tone: StatusPill.Tone
    public let animationEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        progress: Double,
        lineWidth: CGFloat = 6,
        tone: StatusPill.Tone = .info,
        animationEnabled: Bool = true
    ) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.tone = tone
        self.animationEnabled = animationEnabled
    }

    public var body: some View {
        let clamped = min(max(progress, 0), 1)
        let tint = tone.fillColor
        // Subtler "breathing" background — 0.08 vs the older 0.15 —
        // so the active trim reads first.
        ZStack {
            Circle()
                .stroke(
                    tint.opacity(0.08),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            Circle()
                .trim(from: 0, to: CGFloat(clamped))
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(
                    (reduceMotion || !animationEnabled) ? nil : .linear(duration: 0.25),
                    value: clamped
                )
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Tone color access (matches StatusPill)

extension StatusPill.Tone {
    /// Public surface so other components (e.g. CountdownRing,
    /// AnimatedNFCGlyph) can share the same tone palette without
    /// duplicating the lookup.
    var publicFillColor: Color { fillColor }
}

#if DEBUG
#Preview {
    HStack {
        CountdownRing(progress: 0.95).frame(width: 60, height: 60)
        CountdownRing(progress: 0.50, tone: .positive).frame(width: 60, height: 60)
        CountdownRing(progress: 0.10, tone: .warning).frame(width: 60, height: 60)
    }
    .padding()
}
#endif
