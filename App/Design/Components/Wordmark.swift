//
//  Wordmark.swift
//  ExpresScan
//
//  Animated "ExpresScan" gradient text mirroring the web's AuroraText
//  treatment (`expressync/components/magicui/aurora-text.tsx`). On iOS
//  26 we render the wordmark with a `LinearGradient` foreground style;
//  the `AnimatedWordmark` variant drives the gradient endpoints from a
//  `TimelineView(.animation)` for a left-to-right flow on the same 8 s
//  cycle the web uses (`--aurora-speed: 8s`).
//
//  Reduce-motion fallback: a static gradient (no flow). The brand still
//  reads as a member of the family without animation noise.
//

import SwiftUI

public struct Wordmark: View {

    public enum Size: Sendable {
        case small   // .callout
        case medium  // .title3
        case large   // .largeTitle bold

        var font: Font {
            switch self {
            case .small:  return .callout.weight(.bold)
            case .medium: return .title3.weight(.bold)
            case .large:  return .largeTitle.weight(.bold)
            }
        }
    }

    public let text: String
    public let size: Size

    public init(text: String = "ExpresScan", size: Size = .medium) {
        self.text = text
        self.size = size
    }

    public var body: some View {
        Text(text)
            .font(size.font)
            .foregroundStyle(brandGradient)
            .accessibilityLabel(text)
    }

    private var brandGradient: LinearGradient {
        // Cyan → green → cyan. The previous violet middle stop read as a
        // darker-blue band against the cyan endpoints; matches the
        // simplified palette used in `BrandLogo`.
        LinearGradient(
            colors: [
                ColorPalette.primaryCyan,
                ColorPalette.voltGreen,
                ColorPalette.primaryCyan,
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// Wordmark with a true left-to-right gradient flow. Slightly more
/// expensive (drives a TimelineView every frame) — use it on hero
/// surfaces only (Welcome, splash). Compact contexts can use plain
/// `Wordmark` and skip the per-frame redraw.
public struct AnimatedWordmark: View {

    public let text: String
    public let size: Wordmark.Size

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(text: String = "ExpresScan", size: Wordmark.Size = .large) {
        self.text = text
        self.size = size
    }

    public var body: some View {
        if reduceMotion {
            Wordmark(text: text, size: size)
        } else {
            TimelineView(.animation) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 8) / 8
                Text(text)
                    .font(size.font)
                    .foregroundStyle(
                        LinearGradient(
                            colors: brandColors,
                            startPoint: UnitPoint(x: phase, y: 0.5),
                            endPoint: UnitPoint(x: phase + 1, y: 0.5)
                        )
                    )
                    .accessibilityLabel(text)
            }
        }
    }

    private var brandColors: [Color] {
        // Cyan → green → cyan. Mirror of `BrandLogo.brandColors` after
        // dropping the violet stop.
        [
            ColorPalette.primaryCyan,
            ColorPalette.voltGreen,
            ColorPalette.primaryCyan,
        ]
    }
}

#if DEBUG
#Preview("Wordmark sizes") {
    VStack(spacing: 16) {
        Wordmark(size: .small)
        Wordmark(size: .medium)
        AnimatedWordmark(size: .large)
    }
    .padding()
}
#endif
