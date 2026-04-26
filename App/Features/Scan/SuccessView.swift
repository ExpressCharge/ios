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
    public let onScanAnother: () -> Void
    public let onBackToReady: () -> Void

    @State private var checkmarkScale: CGFloat = 0.5

    public init(
        result: EnrichedScanResult,
        onScanAnother: @escaping () -> Void = {},
        onBackToReady: @escaping () -> Void = {}
    ) {
        self.result = result
        self.onScanAnother = onScanAnother
        self.onBackToReady = onBackToReady
    }

    public var body: some View {
        ZStack {
            ColorPalette.background.ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(ColorPalette.voltGreen)
                    .frame(width: 120, height: 120)
                    .scaleEffect(checkmarkScale)
                    .onAppear {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                            checkmarkScale = 1.0
                        }
                    }
                    .accessibilityLabel("Scan successful")

                customerCard
                    .padding(.horizontal, Spacing.lg)

                Spacer()

                VStack(spacing: Spacing.sm) {
                    Button(action: onScanAnother) {
                        Text("Scan another")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .foregroundStyle(.white)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                    .fill(ColorPalette.primaryCyan)
                            )
                    }
                    .buttonStyle(.plain)

                    Button("Back to ready", action: onBackToReady)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xl)
            }
        }
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
                            .fill(ColorPalette.accentTeal)
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
