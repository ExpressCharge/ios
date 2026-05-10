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
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background)
            .clipShape(Capsule())
            .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Variants

    private var resolvedVariant: Variant {
        if ownerRole == "admin" { return .admin }
        let code = (planCode ?? "expresscharge").lowercased()
        if code.contains("plus") || code.contains("+") { return .plus }
        if code.contains("ac") { return .ac }
        return .standard
    }

    private var label: String {
        switch resolvedVariant {
        case .admin: return "Admin"
        case .plus: return planName ?? "ExpressCharge+"
        case .ac: return planName ?? "ExpressChargeAC"
        case .standard: return planName ?? "ExpressCharge"
        }
    }

    private var accessibilityLabel: String {
        switch resolvedVariant {
        case .admin: return "Plan: Admin"
        case let other:
            return "Plan: \(label) (\(String(describing: other)))"
        }
    }

    @ViewBuilder
    private var background: some View {
        switch resolvedVariant {
        case .admin:
            // Admin: brand gradient (cyan → volt green)
            LinearGradient(
                colors: [ColorPalette.primaryCyan, ColorPalette.voltGreen],
                startPoint: .leading,
                endPoint: .trailing
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
