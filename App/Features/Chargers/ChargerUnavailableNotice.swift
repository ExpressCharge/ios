//
//  ChargerUnavailableNotice.swift
//  ExpresScan
//
//  Replacement body for the charger detail screen when the charger
//  is offline or out of service. Hides reservations + start/stop CTA
//  and explains the state with a refresh affordance.
//

import SwiftUI

struct ChargerUnavailableNotice: View {

    enum Reason: Equatable, Sendable {
        case offline(lastSeen: Date?)
        case outOfService
    }

    let reason: Reason
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(toneColor)
                Text(title)
                    .font(.headline)
            }
            Text(body(now: Date()))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onRefresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
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
        case .offline:      return ColorPalette.mutedForeground
        case .outOfService: return ColorPalette.destructiveRose
        }
    }

    private func body(now: Date) -> String {
        switch reason {
        case .offline(let lastSeen):
            if let lastSeen {
                let rel = Self.relative.localizedString(for: lastSeen, relativeTo: now)
                return "We haven't heard from this charger \(rel). It can't accept commands until it reconnects."
            }
            return "This charger isn't reachable right now. Try again in a moment."
        case .outOfService:
            return "This charger is reporting a fault. Reservations and remote starts are paused. Contact your site admin if this persists."
        }
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}
