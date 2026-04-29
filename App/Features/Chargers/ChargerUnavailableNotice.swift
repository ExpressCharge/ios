//
//  ChargerUnavailableNotice.swift
//  ExpresScan
//
//  Replacement body for the charger detail screen when the charger
//  is offline or out of service. Hides reservations + start/stop CTA
//  and explains the state. Refresh is available from the nav-bar
//  toolbar button — no in-card refresh affordance.
//

import SwiftUI

struct ChargerUnavailableNotice: View {

    enum Reason: Equatable, Sendable {
        case offline
        case outOfService
    }

    let reason: Reason

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(toneColor)
                Text(title)
                    .font(.headline)
            }
            Text(bodyText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(toneColor.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(toneColor.opacity(0.4), lineWidth: 1)
        )
    }

    private var systemImage: String {
        switch reason {
        case .offline:      return "wifi.slash"
        case .outOfService: return "exclamationmark.triangle.fill"
        }
    }

    private var title: String {
        switch reason {
        case .offline:      return "Charger offline"
        case .outOfService: return "Charger out of service"
        }
    }

    private var toneColor: Color {
        switch reason {
        case .offline:      return ColorPalette.destructiveRose
        case .outOfService: return ColorPalette.warningAmber
        }
    }

    private var bodyText: String {
        switch reason {
        case .offline:
            return "This charger is currently offline. Wait for it to come back online and refresh to check its status."
        case .outOfService:
            return "This charger is reporting a fault. Reservations and remote starts are paused. Contact your site admin if this persists."
        }
    }
}
