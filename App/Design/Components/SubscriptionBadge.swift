//
//  SubscriptionBadge.swift
//  ExpresScan
//
//  Compact badge for the success-screen subscription summary. Uses the
//  `StatusPill` primitive under the hood; this file maps the
//  `SubscriptionStatus` model enum to a (label, icon, tone) triple so
//  the view is a one-liner.
//
//  Spec: `50-ios.md` § "UX details" → "Success".
//  Wire-in (E-app-wire) replaces the `previewStatus` placeholder with
//  the real `EnrichedScanResult.subscription.status`.
//

import Models
import SwiftUI

public struct SubscriptionBadge: View {

    public let status: SubscriptionStatus?
    public let billingTier: BillingTier?

    public init(status: SubscriptionStatus?, billingTier: BillingTier? = nil) {
        self.status = status
        self.billingTier = billingTier
    }

    public var body: some View {
        let info = mapping(for: status)
        StatusPill(label: info.label, systemImage: info.icon, tone: info.tone)
            .accessibilityLabel("Subscription: \(info.label)")
    }

    private struct Display {
        let label: String
        let icon: String
        let tone: StatusPill.Tone
    }

    private func mapping(for status: SubscriptionStatus?) -> Display {
        guard let status else {
            return Display(
                label: "No subscription",
                icon: "questionmark.circle",
                tone: .neutral
            )
        }
        switch status {
        case .active:
            // `comped` is rendered the same way visually but the
            // success screen shows a small "(Comped)" suffix near
            // the plan label — that's owned by the success view.
            return Display(label: "Active", icon: "checkmark.seal.fill", tone: .positive)
        case .pending:
            return Display(label: "Pending", icon: "hourglass", tone: .warning)
        case .terminated:
            return Display(label: "Terminated", icon: "xmark.octagon.fill", tone: .negative)
        case .canceled:
            return Display(label: "Canceled", icon: "xmark.circle.fill", tone: .negative)
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 10) {
        SubscriptionBadge(status: .active)
        SubscriptionBadge(status: .pending)
        SubscriptionBadge(status: .terminated)
        SubscriptionBadge(status: .canceled)
        SubscriptionBadge(status: nil)
    }
    .padding()
}
#endif
