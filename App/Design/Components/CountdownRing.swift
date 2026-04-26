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
//  Skeleton view: takes a `progress` 0…1 directly. E-app-wire feeds the
//  TimelineView-driven percentage from `ScanCoordinator`.
//

import SwiftUI

public struct CountdownRing: View {

    /// 0 = empty, 1 = full. Clamped on read.
    public let progress: Double
    public let lineWidth: CGFloat
    public let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        progress: Double,
        lineWidth: CGFloat = 6,
        tint: Color = ColorPalette.primaryCyan
    ) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.tint = tint
    }

    public var body: some View {
        let clamped = min(max(progress, 0), 1)
        ZStack {
            Circle()
                .stroke(
                    tint.opacity(0.15),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            Circle()
                .trim(from: 0, to: CGFloat(clamped))
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 0.25), value: clamped)
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    HStack {
        CountdownRing(progress: 0.95).frame(width: 60, height: 60)
        CountdownRing(progress: 0.50).frame(width: 60, height: 60)
        CountdownRing(progress: 0.10).frame(width: 60, height: 60)
    }
    .padding()
}
#endif
