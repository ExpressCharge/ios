//
//  SuccessView.swift
//  ExpresScan
//
//  Final "we read the card" screen. Big spring-animated checkmark on
//  top, customer card below: name, status badge, plan label, renewal
//  date.
//
//  Slice N (a640f12) added the matched-geometry icon morph + the 10s
//  auto-dismiss back to ready.
//
//  Slice N+1 adds the chrome:
//    - top-left: native iOS back button (early-dismiss path that
//      cancels the auto-dismiss timer);
//    - top-right: a small `CompactCountdown` ring + remaining-seconds
//      label, tinted white, that depletes with the auto-dismiss;
//    - bottom: a footer row with the card ID (left, monospaced) and
//      the card type (right, friendly-formatted).
//

import Models
import SwiftUI

public struct SuccessView: View {

    public let result: EnrichedScanResult
    public let iconNamespace: Namespace.ID?
    /// Fired ~10s after the view appears (or on back-button tap),
    /// returning to ready. Replaces the manual "Scan another" button
    /// per Slice N.
    public let onDismiss: () -> Void

    /// Seconds the result stays on screen before auto-returning.
    private static let autoDismissSeconds: TimeInterval = 10

    /// Wall-clock deadline at which the view auto-dismisses. Locked to
    /// `.now + autoDismissSeconds` on first appear so a `TimelineView`
    /// can drive the visible countdown.
    @State private var deadline: Date?
    /// Set true once the view has fired `onDismiss`, to suppress
    /// duplicate calls when the timer and the back button race.
    @State private var didDismiss: Bool = false

    public init(
        result: EnrichedScanResult,
        iconNamespace: Namespace.ID? = nil,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.result = result
        self.iconNamespace = iconNamespace
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            ColorPalette.background.ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                Spacer()

                ScanIconView(
                    mode: .result(iconResult(for: result)),
                    size: 120,
                    namespace: iconNamespace
                )

                customerCard
                    .padding(.horizontal, Spacing.lg)

                Spacer()

                cardFooter
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.md)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismissNow()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
            }
            if let deadline {
                ToolbarItem(placement: .topBarTrailing) {
                    TimelineView(.animation(minimumInterval: 1.0)) { context in
                        let remaining = max(0, deadline.timeIntervalSince(context.date))
                        CompactCountdown(
                            progress: remaining / Self.autoDismissSeconds,
                            seconds: Int(remaining.rounded(.up)),
                            tone: .resultDismiss
                        )
                        .onChange(of: remaining <= 0) { _, expired in
                            if expired { dismissNow() }
                        }
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if deadline == nil {
                deadline = Date().addingTimeInterval(Self.autoDismissSeconds)
            }
        }
    }

    /// Single dismiss path. Idempotent — both the auto-dismiss
    /// `TimelineView` callback and the back-button tap go through
    /// here, but `onDismiss` only fires once.
    private func dismissNow() {
        guard !didDismiss else { return }
        didDismiss = true
        onDismiss()
    }

    /// Maps the enriched result onto the four-way result icon palette.
    /// Unknown tag → blue; active sub → green; inactive sub → yellow.
    /// (Failure isn't reachable from here — that's `ErrorView`'s
    /// branch.)
    private func iconResult(for result: EnrichedScanResult) -> ScanIconResult {
        guard result.found, result.tag != nil else { return .unknown }
        guard let status = result.subscription?.status else { return .unknown }
        return status == .active ? .active : .inactive
    }

    private var customerCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Customer name + slug.
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.customer?.displayName ?? "Unknown customer")
                        .font(.headline)
                    if let slug = result.customer?.slug {
                        Text("@\(slug)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                SubscriptionBadge(
                    status: result.subscription?.status,
                    billingTier: result.subscription?.billingTier
                )
            }

            Divider()

            // Plan + renewal.
            HStack(spacing: Spacing.md) {
                infoColumn(
                    title: "Plan",
                    value: result.subscription?.planLabel ?? "—")
                Spacer()
                infoColumn(
                    title: "Renews",
                    value: formattedRenewal(result.subscription?.currentPeriodEndIso))
            }

            // Comped suffix per success spec.
            if result.subscription?.billingTier == .comped {
                Text("Comped")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .foregroundStyle(.white)
                    .background(
                        Capsule(style: .continuous)
                            .fill(ColorPalette.info)
                    )
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(ColorPalette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(ColorPalette.borderSubtle, lineWidth: 1)
        )
    }

    /// Bottom-of-view row: card ID (left, monospaced) and card type
    /// (right, friendly-formatted). Slice N+1.
    private var cardFooter: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(result.idTag)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Card ID \(result.idTag)")
            Spacer()
            Text(formattedCardType(result.tag?.tagType))
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Card type \(formattedCardType(result.tag?.tagType))")
        }
    }

    private func infoColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
        }
    }

    /// Pretty-prints an ISO-8601 instant. Returns `"—"` if nil/parse-fails.
    private func formattedRenewal(_ iso: String?) -> String {
        guard let iso else { return "—" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return iso }

        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .none
        return display.string(from: date)
    }

    /// Maps the wire `tagType` enum strings into the human label shown
    /// in the footer row. Unknown types fall through unchanged so we
    /// never silently drop an unfamiliar value on the floor.
    private func formattedCardType(_ wire: String?) -> String {
        switch wire {
        case "ev_card": return "EV card"
        case "phone_nfc": return "Phone NFC"
        case "guest_qr": return "Guest QR"
        case .none: return "Unknown"
        case .some(let other):
            return
                other
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }
}
