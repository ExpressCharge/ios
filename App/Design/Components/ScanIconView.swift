//
//  ScanIconView.swift
//  ExpresScan
//
//  Wave 6 / Slice N. The single icon that morphs across the entire scan
//  flow: ReadyView's hero, ScanActiveView's countdown center, and the
//  Success/Error result screens. Driven by a `ScanIconMode` enum and
//  matched to a shared `Namespace.ID` so SwiftUI animates its position
//  between sibling views automatically.
//
//  Modes:
//   - `.idle(tone:)`        — the "Ready to Scan" hero. Variable-color
//                             pulse on the SF Symbol; tone is caller's
//                             choice (info / neutral / etc).
//   - `.armed`              — active scan: green tone, with a subtle
//                             1.0 ↔ 1.08 pulse @ 1.5s cycle layered on
//                             top of the symbol's variable-color sweep.
//   - `.result(.unknown)`   — blue checkmark (info tone).
//   - `.result(.active)`    — green checkmark (positive / voltGreen).
//   - `.result(.inactive)`  — yellow checkmark (warning / amber).
//   - `.result(.failure)`   — red x (negative / destructiveRose).
//
//  Honors `accessibilityReduceMotion`: the variable-color sweep, the
//  scale pulse, and the symbol-replace effect all collapse to static.
//

import SwiftUI

public enum ScanIconResult: Equatable, Sendable {
    /// Tag scanned but no resolved customer / unknown card.
    case unknown
    /// Active subscription.
    case active
    /// Subscription present but inactive (pending / canceled / terminated).
    case inactive
    /// Scan or communication failure.
    case failure
}

public enum ScanIconMode: Equatable, Sendable {
    case idle(tone: StatusPill.Tone)
    case armed
    case result(ScanIconResult)
}

public struct ScanIconView: View {

    public let mode: ScanIconMode
    public let size: CGFloat
    public let namespace: Namespace.ID?
    public let matchedID: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        mode: ScanIconMode,
        size: CGFloat = 96,
        namespace: Namespace.ID? = nil,
        matchedID: String = "scanIcon"
    ) {
        self.mode = mode
        self.size = size
        self.namespace = namespace
        self.matchedID = matchedID
    }

    public var body: some View {
        let symbol = symbolName(for: mode)
        let tint = tint(for: mode)

        Group {
            if let ns = namespace {
                iconImage(symbol: symbol, tint: tint)
                    .matchedGeometryEffect(id: matchedID, in: ns)
            } else {
                iconImage(symbol: symbol, tint: tint)
            }
        }
        .accessibilityLabel(accessibilityLabel(for: mode))
    }

    @ViewBuilder
    private func iconImage(symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            // Variable-color sweep only on the wave glyph; it doesn't
            // read on a checkmark/x.
            .symbolEffect(
                .variableColor.iterative,
                isActive: !reduceMotion && mode == .armed
            )
            // `replace.byLayer` makes the wave→check / wave→x swap feel
            // crisp instead of a hard cut. Bounce on first appearance
            // for results so the user notices the resolution.
            .symbolEffect(.bounce, options: .nonRepeating, value: bounceTrigger(for: mode))
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace.byLayer))
            .scaleEffect(scaleEffectValue)
            .shadow(color: tint.opacity(0.40), radius: 16)
            .animation(.easeOut(duration: 0.6), value: tint)
    }

    /// Drives the 1.0 ↔ 1.08 pulse on `.armed`. Implemented with a
    /// `TimelineView` so the value-changes-once animation pattern doesn't
    /// require external state. We DON'T wrap the whole view in a
    /// TimelineView (that defeats matchedGeometry) — instead we read the
    /// scale from a tiny per-render computation. SwiftUI redraws on the
    /// containing TimelineView when the calling site provides one
    /// (ScanActiveView already uses one for the countdown).
    private var scaleEffectValue: CGFloat {
        guard !reduceMotion, case .armed = mode else { return 1.0 }
        // 1.5s sine-wave between 1.0 and 1.08.
        let t = Date().timeIntervalSinceReferenceDate
        let phase = (t.truncatingRemainder(dividingBy: 1.5)) / 1.5
        let s = sin(phase * 2 * .pi)
        return 1.0 + 0.04 * (1.0 + s) // 1.0 … 1.08
    }

    private func symbolName(for mode: ScanIconMode) -> String {
        switch mode {
        case .idle, .armed:
            return "wave.3.right.circle.fill"
        case .result(.unknown), .result(.active), .result(.inactive):
            return "checkmark.circle.fill"
        case .result(.failure):
            return "xmark.circle.fill"
        }
    }

    private func tint(for mode: ScanIconMode) -> Color {
        switch mode {
        case .idle(let tone):
            return tone.publicFillColor
        case .armed:
            return ColorPalette.success
        case .result(.unknown):
            return ColorPalette.info
        case .result(.active):
            return ColorPalette.voltGreen
        case .result(.inactive):
            return ColorPalette.warningAmber
        case .result(.failure):
            return ColorPalette.destructiveRose
        }
    }

    /// Stable per-mode token so `.bounce` re-fires on each transition.
    private func bounceTrigger(for mode: ScanIconMode) -> Int {
        switch mode {
        case .idle:               return 0
        case .armed:              return 1
        case .result(.unknown):   return 2
        case .result(.active):    return 3
        case .result(.inactive):  return 4
        case .result(.failure):   return 5
        }
    }

    private func accessibilityLabel(for mode: ScanIconMode) -> String {
        switch mode {
        case .idle:               return "NFC reader ready"
        case .armed:              return "Scan a card now"
        case .result(.unknown):   return "Card scanned, account not found"
        case .result(.active):    return "Active subscription"
        case .result(.inactive):  return "Subscription inactive"
        case .result(.failure):   return "Scan failed"
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 24) {
        ScanIconView(mode: .idle(tone: .info))
        ScanIconView(mode: .armed)
        ScanIconView(mode: .result(.unknown))
        ScanIconView(mode: .result(.active))
        ScanIconView(mode: .result(.inactive))
        ScanIconView(mode: .result(.failure))
    }
    .padding()
}
#endif
