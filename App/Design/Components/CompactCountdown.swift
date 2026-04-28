//
//  CompactCountdown.swift
//  ExpresScan
//
//  Small toolbar-friendly countdown indicator: a ring around a
//  remaining-seconds label. Used in ScanActiveView's top-right (green
//  tint, depleting as the scan window closes) and on the result views
//  (white tint, depleting as the 10s auto-dismiss approaches).
//
//  About the size of a native nav-bar button — `~28pt` ring outer
//  diameter — so it sits comfortably as a `ToolbarItem` next to a
//  back button without crowding the title.
//

import SwiftUI

/// Compact ring + text countdown for nav-bar use. Pure presentation —
/// the caller drives `progress` (0…1, where 1 is full and 0 is
/// expired) and `seconds` (the integer label rendered next to the
/// ring).
public struct CompactCountdown: View {

    /// 0 = empty (expired), 1 = full. Clamped on read.
    public let progress: Double
    /// Whole seconds remaining; rendered as `"Ns"` next to the ring.
    public let seconds: Int
    /// Tone drives the ring + label color.
    public let tone: Tone

    public enum Tone: Sendable {
        /// Green — used on `ScanActiveView` while a scan is armed.
        case scanArmed
        /// White-on-translucent — used on the result views during the
        /// 10s auto-dismiss countdown.
        case resultDismiss

        var ringColor: Color {
            switch self {
            case .scanArmed:      return ColorPalette.voltGreen
            case .resultDismiss:  return Color.white
            }
        }
        var trackColor: Color { ringColor.opacity(0.20) }
        var labelColor: Color { ringColor }
    }

    public init(progress: Double, seconds: Int, tone: Tone) {
        self.progress = progress
        self.seconds = seconds
        self.tone = tone
    }

    public var body: some View {
        let clamped = min(max(progress, 0), 1)
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(
                        tone.trackColor,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                Circle()
                    .trim(from: 0, to: CGFloat(clamped))
                    .stroke(
                        tone.ringColor,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)

            Text("\(seconds)s")
                .font(.callout.monospacedDigit().weight(.medium))
                .foregroundStyle(tone.labelColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(seconds) seconds remaining")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#if DEBUG
#Preview("CompactCountdown — both tones") {
    VStack(spacing: 16) {
        CompactCountdown(progress: 0.85, seconds: 9, tone: .resultDismiss)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
        CompactCountdown(progress: 0.40, seconds: 24, tone: .scanArmed)
        CompactCountdown(progress: 0.05, seconds: 1, tone: .scanArmed)
    }
    .padding()
}
#endif
