//
//  ReservationsCard.swift
//  ExpresScan
//
//  Wave 6 / Slice J — upcoming reservations card on the customer-style
//  `ChargerDetailView`. Up to 3 rows visible inline; overflow under a
//  `DisclosureGroup`. The card is hidden entirely while a session is
//  charging — the parent view replaces it with a small "Next" pill on
//  the hero.
//

import SwiftUI

struct ReservationsCard: View {

    let reservations: [Reservation]
    let actionInFlight: Bool
    let onCancel: (Reservation) -> Void

    @State private var pendingCancel: Reservation?
    @State private var showOverflow: Bool = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Upcoming reservations")
                .font(.headline)
                .padding(.horizontal, Spacing.base)

            VStack(spacing: 0) {
                ForEach(visibleReservations) { res in
                    row(res)
                    if res.id != visibleReservations.last?.id {
                        Divider().padding(.leading, Spacing.base)
                    }
                }
                if reservations.count > 3 {
                    DisclosureGroup(isExpanded: $showOverflow) {
                        VStack(spacing: 0) {
                            ForEach(overflowReservations) { res in
                                Divider().padding(.leading, Spacing.base)
                                row(res)
                            }
                        }
                    } label: {
                        Text("Show \(reservations.count - 3) more")
                            .font(.subheadline)
                            .foregroundStyle(ColorPalette.primaryCyan)
                    }
                    .padding(.horizontal, Spacing.base)
                    .padding(.vertical, Spacing.sm)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(ColorPalette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(ColorPalette.borderSubtle)
                    )
            )
        }
        .confirmationDialog(
            "Cancel this reservation?",
            isPresented: Binding(
                get: { pendingCancel != nil },
                set: { if !$0 { pendingCancel = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingCancel
        ) { res in
            Button("Cancel reservation", role: .destructive) {
                onCancel(res)
                pendingCancel = nil
            }
            Button("Keep it", role: .cancel) { pendingCancel = nil }
        } message: { res in
            Text(messageFor(res))
        }
    }

    private var visibleReservations: [Reservation] {
        Array(reservations.prefix(3))
    }

    private var overflowReservations: [Reservation] {
        Array(reservations.dropFirst(3))
    }

    @ViewBuilder
    private func row(_ res: Reservation) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(timeWindowText(res))
                    .font(.body.weight(.medium))
                Text(labelLine(res))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let tag = res.idTag {
                    Text(tag)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if res.isCancelable {
                Button(role: .destructive) {
                    pendingCancel = res
                } label: {
                    Text("Cancel")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(actionInFlight)
            }
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.sm)
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    private func timeWindowText(_ res: Reservation) -> String {
        let start = Self.timeFormatter.string(from: res.startsAt)
        let end = Self.timeFormatter.string(from: res.endsAt)
        let day = Self.dayFormatter.string(from: res.startsAt)
        return "\(day), \(start) – \(end)"
    }

    private func labelLine(_ res: Reservation) -> String {
        if res.isBlackout { return "Blackout" }
        return res.customerLabel ?? "Reserved"
    }

    private func messageFor(_ res: Reservation) -> String {
        if res.isBlackout {
            return "Cancel this admin blackout window?"
        }
        return "Cancel \(res.customerLabel ?? "this")'s reservation?"
    }
}
