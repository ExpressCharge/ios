//
//  SuccessView.swift
//  ExpresScan
//
//  Final "we read the card" screen. Big spring-animated checkmark on
//  top, customer card below: name, status badge, plan label, renewal
//  date. Manual dismiss only — NO auto-return per the wireframes.
//
//  Skeleton ships layout. E-app-wire passes a real
//  `EnrichedScanResult` from the coordinator.
//
//  Spec: `50-ios.md` § "UX details" → "Success".
//

import SwiftUI

import Models

public struct SuccessView: View {

    public let result: EnrichedScanResult
    public let iconNamespace: Namespace.ID?
    /// Fired ~10s after the view appears, returning to ready. Replaces
    /// the manual "Scan another" button per Slice N.
    public let onAutoDismiss: () -> Void

    /// Seconds the result stays on screen before auto-returning.
    private static let autoDismissSeconds: UInt64 = 10

    public init(
        result: EnrichedScanResult,
        iconNamespace: Namespace.ID? = nil,
        onAutoDismiss: @escaping () -> Void = {}
    ) {
        self.result = result
        self.iconNamespace = iconNamespace
        self.onAutoDismiss = onAutoDismiss
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
            }
        }
        .task {
            // Auto-dismiss timer. Cancelling the task (view dismount,
            // user navigates elsewhere, coordinator state change)
            // aborts the sleep before `onAutoDismiss` fires.
            try? await Task.sleep(
                nanoseconds: Self.autoDismissSeconds * 1_000_000_000
            )
            guard !Task.isCancelled else { return }
            onAutoDismiss()
        }
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
                infoColumn(title: "Plan",
                          value: result.subscription?.planLabel ?? "—")
                Spacer()
                infoColumn(title: "Renews",
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
}
