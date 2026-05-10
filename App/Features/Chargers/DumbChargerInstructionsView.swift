//
//  DumbChargerInstructionsView.swift
//  ExpresScan
//
//  Migration 0043 — replacement body for the charger detail screen
//  when `vm.availability == .dumbCharger`. Tesla Wall Connectors and
//  other unmanaged chargers don't speak OCPP, so there's no Start/Stop
//  CTA, no session, no reservations. The screen instead surfaces a
//  "just plug in" instructions card and a Free badge so the customer
//  knows what to do at a glance.
//

import SwiftUI

struct DumbChargerInstructionsView: View {

    /// Numbered steps customers see at the unit. Mirrors
    /// `src/lib/content/dumb-charger-instructions.ts` on the server,
    /// but kept independent so iOS-idiomatic copy can drift.
    private let steps: [String] = [
        "Plug in your cable.",
        "Your car negotiates power automatically.",
        "Unplug when you're done.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "powerplug.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ColorPalette.info)
                Text("Plug in. Charge. Free.")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text("\(idx + 1).")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .trailing)
                        Text(step)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: Spacing.sm) {
                Label("Free charging", systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(ColorPalette.voltGreen)
                Spacer(minLength: 0)
                Link(
                    "Need help?",
                    destination: URL(string: "mailto:support@example.com")!
                )
                .font(.caption)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(ColorPalette.info.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(ColorPalette.info.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}
