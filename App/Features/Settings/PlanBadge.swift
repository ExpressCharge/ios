//
//  PlanBadge.swift
//  ExpresScan
//
//  Brand-tinted plan tier pill rendered next to the user's display
//  name in the Settings AccountIdentityCard.
//
//  Variants:
//    - admin role            → "Admin" (cyan + green brand gradient)
//    - planCode "expresscharge" / null → "ExpressCharge" (cyan)
//    - planCode "*plus*"     → "ExpressCharge+" (cyan + green gradient)
//    - planCode "*ac*"       → "ExpressChargeAC" (volt-green accent)
//    - any other code        → planName (or humanised code)
//
//  Plan info comes from `/api/devices/me`'s new `ownerRole` /
//  `planCode` / `planName` fields (server change shipped 2026-05).
//  Older server builds return null for all three; the badge falls
//  back to a neutral "ExpressCharge" so signed-in customers always
//  see a plan, even pre-Lago-sync.
//

import SwiftUI

struct PlanBadge: View {

    let ownerRole: String?
    let planCode: String?
    let planName: String?

    var body: some View {
        if let variant = resolvedVariant {
            Text(label(for: variant))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(background(for: variant))
                .clipShape(Capsule())
                .accessibilityLabel("Plan: \(label(for: variant))")
        }
    }

    // MARK: - Variants

    /// Returns `nil` when we have no concrete plan signal. Hiding the
    /// badge in that case avoids showing a misleading "ExpressCharge"
    /// pill to admin accounts (whose role hasn't decoded yet) or to
    /// users on a server build that doesn't return plan fields.
    private var resolvedVariant: Variant? {
        if ownerRole == "admin" { return .admin }
        guard let code = planCode?.lowercased(), !code.isEmpty else {
            return nil
        }
        if code.contains("plus") || code.contains("+") { return .plus }
        if code.contains("ac") { return .ac }
        return .standard
    }

    private func label(for variant: Variant) -> String {
        switch variant {
        case .admin: return "Admin"
        case .plus: return planName ?? "ExpressCharge+"
        case .ac: return planName ?? "ExpressChargeAC"
        case .standard: return planName ?? "ExpressCharge"
        }
    }

    @ViewBuilder
    private func background(for variant: Variant) -> some View {
        switch variant {
        case .admin:
            // Admin: brand gradient on the diagonal so it reads as
            // distinct from `.plus` (which uses the same colours on a
            // horizontal sweep).
            LinearGradient(
                colors: [ColorPalette.primaryCyan, ColorPalette.voltGreen],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .plus:
            // Plus: brand gradient (cyan → volt green) — premium tier.
            LinearGradient(
                colors: [ColorPalette.primaryCyan, ColorPalette.voltGreen],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .ac:
            // AC: volt-green flat. The fastest tier — wears the most
            // saturated brand colour.
            ColorPalette.voltGreen
        case .standard:
            // Standard ExpressCharge: brand cyan.
            ColorPalette.primaryCyan
        }
    }

    private enum Variant {
        case admin
        case standard
        case plus
        case ac
    }
}
