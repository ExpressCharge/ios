//
//  ActiveSessionCard.swift
//  ExpresScan
//
//  Two stacked cards shown while the charger is delivering power:
//
//   1. A volt-green-tinted telemetry card with a 2x2 stats grid
//      (amps · elapsed / kW · kWh) and a `Charging` label.
//   2. A "who is charging" row with an initials avatar.
//
//  Mirrors the web admin's connector card definition-list layout
//  (`expresscharge/islands/ConnectorCard.tsx`) at iOS proportions.
//

import SwiftUI

struct ActiveSessionCard: View {

    let session: ChargerSession
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            telemetryCard
            customerCard
        }
    }

    // MARK: - Telemetry

    private var telemetryCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            statsGrid
            HStack(spacing: Spacing.xs) {
                LivePulseDot()
                Text("Charging")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ColorPalette.voltGreen)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(ColorPalette.voltGreen.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(ColorPalette.glowGreen.opacity(0.4), lineWidth: 1)
        )
    }

    private var statsGrid: some View {
        Grid(horizontalSpacing: Spacing.lg, verticalSpacing: Spacing.md) {
            GridRow {
                ampsCell
                statCell(value: elapsedValue, unit: nil)
            }
            GridRow {
                statCell(value: kwValue, unit: "kW")
                statCell(value: kwhValue, unit: "kWh")
            }
        }
    }

    /// Custom amps cell — renders `{current}/{max} A` when the wire
    /// supplies a max-amp cap, otherwise falls back to the standard
    /// `{value} A` cell so older server builds still render cleanly.
    @ViewBuilder
    private var ampsCell: some View {
        if let max = session.maxAmps, max > 0 {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(ampsValue)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ColorPalette.foreground)
                Text("/ \(max)")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("A")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            statCell(value: ampsValue, unit: "A")
        }
    }

    private func statCell(value: String, unit: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ColorPalette.foreground)
            if let unit {
                Text(unit)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Customer

    private var customerCard: some View {
        HStack(spacing: Spacing.md) {
            InitialsAvatar(name: session.customerName)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.headline)
                    .lineLimit(1)
                if let tag = session.idTag, !tag.isEmpty {
                    Text(tag)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(ColorPalette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(ColorPalette.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: - Display helpers

    private var ampsValue: String {
        session.derivedAmps.map { "\($0)" } ?? "—"
    }

    private var kwValue: String {
        guard let kw = session.kw else { return "—" }
        return String(format: "%.1f", kw)
    }

    private var kwhValue: String {
        guard let kwh = session.kwh else { return "—" }
        return String(format: "%.1f", kwh)
    }

    private var elapsedValue: String {
        let seconds: Int
        if let started = session.startedAt {
            seconds = max(0, Int(now.timeIntervalSince(started)))
        } else if let fallback = session.elapsedSec {
            seconds = fallback
        } else {
            return "—"
        }
        return Self.elapsedFormatter.string(from: TimeInterval(seconds)) ?? "—"
    }

    private var displayName: String {
        let name = session.customerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty { return name }
        return "Unknown driver"
    }

    private static let elapsedFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.allowedUnits = [.hour, .minute]
        f.zeroFormattingBehavior = .dropAll
        return f
    }()
}
