//
//  ChargerDetailView.swift
//  ExpresScan
//
//  Wave 6 / Slice J — the customer-style charger detail screen. Hero
//  layout: identity row → big StatusHero with a hero-sized
//  Start/Stop CTA → live telemetry while charging → reservations card
//  (hidden during charging; replaced by a "Next: …" pill on the hero).
//
//  Layout invariant: this is `ScrollView { LazyVStack(...) }` — never a
//  plain `VStack`. At AX5 / Slide-Over the hero alone exceeds the
//  visible safe area.
//

import SwiftUI

struct ChargerDetailView: View {

    let entry: ChargerListEntry

    @Environment(\.app) private var app
    @State private var viewModel: ChargerDetailViewModel?
    @State private var showStopConfirm: Bool = false

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm: vm)
            } else {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(entry.label)
        .navigationBarTitleDisplayMode(.inline)
        .expressBackground()
        .task {
            if viewModel == nil {
                let vm = ChargerDetailViewModel(entry: entry, api: app.api)
                self.viewModel = vm
                await vm.bootstrap()
            }
        }
    }

    @ViewBuilder
    private func content(vm: ChargerDetailViewModel) -> some View {
        @Bindable var bound = vm

        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                identityRow

                heroSection(vm: vm)

                if vm.isCharging {
                    telemetrySection(vm: vm)
                }

                if !vm.isCharging && !vm.reservations.isEmpty {
                    ReservationsCard(
                        reservations: vm.reservations,
                        actionInFlight: vm.actionInFlight,
                        onCancel: { res in
                            Task { await vm.cancelReservation(res.reservationId, confirmed: true) }
                        }
                    )
                }

                if case .error(let message) = vm.loadState {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(ColorPalette.warningAmber)
                        .padding(.horizontal, Spacing.base)
                }
            }
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.lg)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: vm.heroState)
            .animation(.default, value: vm.reservations)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .refreshable { await vm.refresh() }
        .sheet(isPresented: $bound.pickerVisible) {
            CustomerPickerSheet(customers: vm.customers) { customer in
                Task { await vm.submitStart(customer: customer) }
            }
        }
        .confirmationDialog(
            "Stop charging?",
            isPresented: $showStopConfirm,
            titleVisibility: .visible
        ) {
            Button("Stop charging", role: .destructive) {
                Task { await vm.stopCharging(confirmed: true) }
            }
            Button("Keep charging", role: .cancel) {}
        } message: {
            stopConfirmMessage(vm: vm)
        }
    }

    // MARK: - Sections

    private var identityRow: some View {
        HStack(spacing: Spacing.xs) {
            Text(identityLine)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
    }

    @ViewBuilder
    private func heroSection(vm: ChargerDetailViewModel) -> some View {
        VStack(spacing: Spacing.md) {
            StatusHero(
                state: vm.heroState,
                title: heroTitle(vm: vm),
                secondary: heroSecondary(vm: vm)
            )

            if vm.isCharging, let next = nextReservationPill(vm: vm) {
                Text(next)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        Capsule().fill(ColorPalette.muted)
                    )
            }

            if !vm.isOffline {
                primaryCTA(vm: vm)
            } else {
                PrimaryButton(
                    "Charger offline",
                    systemImage: "wifi.slash",
                    variant: .destructive,
                    state: .disabled,
                    size: .hero,
                    action: {}
                )
            }
        }
    }

    @ViewBuilder
    private func telemetrySection(vm: ChargerDetailViewModel) -> some View {
        TimelineView(.animation(minimumInterval: 1.0)) { context in
            LiveTelemetryRow(
                kwh: kwhDisplay(vm.session?.kwh),
                kw: kwDisplay(vm.session?.kw),
                elapsed: elapsedDisplay(vm.session?.startedAt, fallback: vm.session?.elapsedSec, now: context.date)
            )
        }
    }

    // MARK: - Hero copy + CTA

    @ViewBuilder
    private func primaryCTA(vm: ChargerDetailViewModel) -> some View {
        if vm.isCharging {
            PrimaryButton(
                "Stop charging",
                systemImage: "stop.fill",
                variant: .destructive,
                state: vm.actionInFlight ? .loading : .default,
                size: .hero
            ) {
                showStopConfirm = true
            }
        } else {
            PrimaryButton(
                startButtonLabel(vm: vm),
                systemImage: "bolt.fill",
                variant: .success,
                state: vm.actionInFlight ? .loading : .default,
                size: .hero
            ) {
                Task { await vm.startCharging() }
            }
        }
    }

    private func startButtonLabel(vm: ChargerDetailViewModel) -> String {
        if let res = vm.currentReservation, let label = res.customerLabel {
            return "Start charging (\(label))"
        }
        return "Start charging"
    }

    private func heroTitle(vm: ChargerDetailViewModel) -> String {
        switch vm.heroState {
        case .idle:         return "Idle"
        case .plugged:      return "Plugged in"
        case .charging:     return vm.session?.state == .stopping ? "Stopping" : "Charging"
        case .reserved:     return "Reserved"
        case .outOfService: return vm.isOffline ? "Charger offline" : "Out of service"
        }
    }

    private func heroSecondary(vm: ChargerDetailViewModel) -> String? {
        switch vm.heroState {
        case .reserved:
            guard let res = vm.currentReservation else { return nil }
            let label = res.isBlackout ? "Blackout" : (res.customerLabel ?? "Reserved")
            let until = Self.timeFormatter.string(from: res.endsAt)
            return "Reserved by \(label) — Until \(until)"
        case .charging:
            if let name = vm.session?.customerName { return "Powering \(name)" }
            return nil
        case .outOfService:
            if vm.isOffline, let last = entry.lastSeenAt {
                return "Last seen \(Self.timeFormatter.string(from: last))"
            }
            return nil
        case .idle, .plugged:
            return nil
        }
    }

    private func nextReservationPill(vm: ChargerDetailViewModel) -> String? {
        guard let next = vm.reservations.first else { return nil }
        let label = next.isBlackout ? "Blackout" : (next.customerLabel ?? "Reserved")
        return "Next: \(label) \(Self.timeFormatter.string(from: next.startsAt))"
    }

    @ViewBuilder
    private func stopConfirmMessage(vm: ChargerDetailViewModel) -> some View {
        if let kwh = vm.session?.kwh {
            Text(String(format: "Stop the session at %.1f kWh delivered?", kwh))
        } else {
            Text("Stop the in-progress session?")
        }
    }

    // MARK: - Identity

    private var identityLine: String {
        var bits: [String] = [entry.label]
        bits.append(entry.connectorType?.displayLabel ?? "—")
        bits.append(entry.maxKw.map { String(format: "%.0f kW", $0) } ?? "— kW")
        return bits.joined(separator: " · ")
    }

    // MARK: - Display helpers

    private func kwhDisplay(_ value: Double?) -> String {
        guard let v = value else { return "–" }
        return String(format: "%.1f", v)
    }

    private func kwDisplay(_ value: Double?) -> String {
        guard let v = value else { return "–" }
        return String(format: "%.1f", v)
    }

    private func elapsedDisplay(_ startedAt: Date?, fallback: Int?, now: Date) -> String {
        let seconds: Int
        if let started = startedAt {
            seconds = max(0, Int(now.timeIntervalSince(started)))
        } else if let fb = fallback {
            seconds = fb
        } else {
            return "–"
        }
        return Self.elapsedFormatter.string(from: TimeInterval(seconds)) ?? "–"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let elapsedFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.unitsStyle = .positional
        f.allowedUnits = [.hour, .minute, .second]
        f.zeroFormattingBehavior = .pad
        return f
    }()
}

private extension ChargerListEntry.ConnectorType {
    var displayLabel: String {
        switch self {
        case .ccs:     return "CCS"
        case .j1772:   return "J1772"
        case .nacs:    return "NACS"
        case .chademo: return "CHAdeMO"
        case .type2:   return "Type 2"
        }
    }
}
