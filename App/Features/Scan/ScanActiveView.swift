//
//  ScanActiveView.swift
//  ExpresScan
//
//  Shown when a scan request is armed. The iOS-supplied NFC reader
//  sheet — fired automatically by `ScanCoordinator.handleIncomingScanRequest`
//  → `beginScan()` — IS the primary scan UI. The system sheet covers the
//  bottom ~70 % of the screen, so this view's job is to fill the
//  remaining top band with what iOS doesn't show:
//
//   - Countdown ring driven by the server-stamped `expiresAtEpochMs`,
//     so the user knows how long they have left.
//   - Upward chevron pointing at the iPhone's NFC antenna (top edge),
//     so they know where to hold the card.
//   - Subheading + optional hint pill explaining what the scan is for.
//
//  The system sheet's own Cancel chrome is the primary cancel affordance
//  — that flows through `runScan`'s `.userCanceled` branch into
//  `cancelActiveScan` and notifies the admin web UI. We keep an explicit
//  Cancel button on this screen as a fallback for the moment between
//  request-arrival and the iOS sheet appearing (a single frame in
//  practice).
//
//  Spec: `50-ios.md` § "UX details" → "Scan request".
//

import SwiftUI

import Models

public struct ScanActiveView: View {

    public let request: ScanRequest
    /// 0…1 ring progress; 1 at issuance, 0 at expiry.
    public let progress: Double

    /// Invoked when the user taps the fallback Cancel button. The
    /// system NFC sheet's own Cancel is wired separately via
    /// `NFCService` → `cancelActiveScan`.
    public let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        request: ScanRequest,
        progress: Double,
        onCancel: @escaping () -> Void = {}
    ) {
        self.request = request
        self.progress = progress
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            ColorPalette.background.ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                Spacer().frame(height: Spacing.md)

                // Upward chevron pointing at the NFC antenna (top edge
                // of the iPhone). Sits ABOVE the countdown ring + glyph
                // and breathes continuously: a slow sine-wave drives a
                // synchronised rise+grow / fall+shrink loop. The fixed
                // outer frame absorbs the offset/scale so the layout
                // below stays put. Honors `reduceMotion` — when on,
                // the chevron renders as a static, larger glyph.
                Group {
                    if reduceMotion {
                        chevron(scale: 1.0)
                    } else {
                        TimelineView(.animation) { context in
                            let t = context.date.timeIntervalSinceReferenceDate
                            // 1.6s period — slow enough to feel calm,
                            // fast enough to read as "active".
                            let phase = (t.truncatingRemainder(dividingBy: 1.6)) / 1.6
                            let s = sin(phase * 2 * .pi)
                            // Rises 14pt at peak, sinks 14pt at trough;
                            // scales 0.88…1.12 in lockstep so the
                            // arrow grows as it rises (one breath).
                            let offsetY = -14.0 * s
                            let scale = 1.0 + 0.12 * s
                            chevron(scale: scale)
                                .offset(y: CGFloat(offsetY))
                        }
                    }
                }
                .frame(height: 110)

                ZStack {
                    CountdownRing(progress: progress, lineWidth: 8, tone: .positive)
                        .frame(width: 160, height: 160)
                    AnimatedNFCGlyph(size: 96, tone: .positive)
                }
                .accessibilityLabel("Scan a card now")

                VStack(spacing: Spacing.sm) {
                    Text("Scan a card now")
                        .font(.title.weight(.bold))
                    Text(subheading(for: request))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                }

                if let hint = request.hintLabel {
                    StatusPill(
                        label: hint,
                        systemImage: "tag.fill",
                        tone: .info
                    )
                }

                Spacer()

                Button("Cancel", role: .cancel, action: onCancel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, Spacing.xl)
            }
        }
    }

    /// Static chevron used as the breathing-loop's leaf. Centralised so
    /// reduce-motion and the `TimelineView` branch can't drift apart in
    /// styling.
    private func chevron(scale: Double) -> some View {
        Image(systemName: "chevron.up")
            .font(.system(size: 84, weight: .bold))
            .foregroundStyle(ColorPalette.voltGreen)
            .scaleEffect(scale)
            .accessibilityLabel("Hold card to top of phone")
    }

    private func subheading(for request: ScanRequest) -> String {
        switch request.purpose {
        case .adminLink:
            return "An admin is linking this card to a customer."
        case .customerLink:
            return "Add this card to your account."
        case .login:
            return "Use this card to sign in."
        case .viewCard:
            return "Look up the card's account."
        }
    }
}
