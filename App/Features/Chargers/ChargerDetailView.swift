//
//  ChargerDetailView.swift
//  ExpresScan
//
//  Customer-style charger detail screen. Top-level body switches on
//  `vm.availability`:
//    * `.ready`         → hero + (active-session card | reservations)
//                         + inline Start/Stop CTA
//    * `.offline` /
//      `.outOfService` → hero + `ChargerUnavailableNotice` (no CTA)
//
//  Layout invariant: `ScrollView { LazyVStack(...) }` — at AX5 the
//  hero alone exceeds the visible safe area.
//

import Networking
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Navigate — opens Apple Maps preferring the structured
            // address (so the user sees "123 Main St" rather than a
            // pin-drop), falling back to lat/lon when only coords are
            // available. Hidden entirely when the charger has neither,
            // matching the plan's "no empty navigate button" rule.
            if let mapsURL = mapsNavigationURL(for: entry) {
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: mapsURL) {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond")
                            .accessibilityLabel("Navigate to charger")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let vm = viewModel {
                        Task { await vm.refresh() }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .accessibilityLabel("Refresh")
                }
                .disabled(viewModel?.loadState == .loading)
            }
        }
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
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                pageTitle

                ChargerHero(
                    heroState: vm.heroState,
                    isOffline: vm.isOffline,
                    connectors: vm.connectors,
                    formFactor: vm.entry.formFactor
                )

                switch vm.availability {
                case .ready:
                    readyBody(vm: vm)
                case .offline:
                    ChargerUnavailableNotice(reason: .offline)
                case .outOfService:
                    ChargerUnavailableNotice(reason: .outOfService)
                case .dumbCharger:
                    // Migration 0043 — unmanaged chargers (Tesla Wall
                    // Connectors etc.). No CTA reachable from this branch
                    // because `readyBody` (which renders the Start/Stop
                    // button via `primaryCTA`) is never called.
                    DumbChargerInstructionsView()
                }

                if case .error(let message, let raw) = vm.loadState {
                    errorBanner(message: message, raw: raw)
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

    @ViewBuilder
    private func readyBody(vm: ChargerDetailViewModel) -> some View {
        if vm.isCharging, let session = vm.session {
            TimelineView(.animation(minimumInterval: 1.0)) { context in
                ActiveSessionCard(session: session, now: context.date)
            }
        } else {
            if !vm.reservations.isEmpty {
                ReservationsCard(
                    reservations: vm.reservations,
                    actionInFlight: vm.actionInFlight,
                    onCancel: { res in
                        Task { await vm.cancelReservation(res.reservationId, confirmed: true) }
                    }
                )
            }
            if hasNFCCapability {
                nfcAvailableNotice
            }
        }

        primaryCTA(vm: vm)
    }

    private var hasNFCCapability: Bool {
        entry.capabilities?.contains("scanner") ?? false
    }

    private var nfcAvailableNotice: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: "wave.3.right.circle.fill")
                .font(.title3)
                .foregroundStyle(ColorPalette.primaryCyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tap your card")
                    .font(.subheadline.weight(.semibold))
                Text("This charger reads RFID cards — tap one to start without using the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(ColorPalette.primaryCyan.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(ColorPalette.primaryCyan.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Sections

    private var pageTitle: some View {
        Text(entry.label)
            .font(.largeTitle.weight(.bold))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func errorBanner(message: String, raw: APIError?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(message)
                    .font(.subheadline)
            }
            .foregroundStyle(ColorPalette.destructiveRose)
            AdminErrorDetail(error: raw)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(ColorPalette.destructiveRose.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(ColorPalette.destructiveRose.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - CTA

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

    @ViewBuilder
    private func stopConfirmMessage(vm: ChargerDetailViewModel) -> some View {
        if let kwh = vm.session?.kwh {
            Text(String(format: "Stop the session at %.1f kWh delivered?", kwh))
        } else {
            Text("Stop the in-progress session?")
        }
    }

    /// Build an Apple Maps URL for the charger's location. Prefers the
    /// formatted `address` (e.g. "123 Main St, San Francisco, CA, US")
    /// because Maps renders the route to a labelled landmark; falls
    /// back to the lat/lon pin when only coordinates are populated.
    /// Returns `nil` when neither is available — the toolbar item then
    /// hides itself rather than showing a disabled button.
    private func mapsNavigationURL(for entry: ChargerListEntry) -> URL? {
        if let address = entry.address?.trimmingCharacters(in: .whitespacesAndNewlines),
            !address.isEmpty
        {
            var components = URLComponents(string: "https://maps.apple.com/")
            components?.queryItems = [
                URLQueryItem(name: "address", value: address),
                URLQueryItem(name: "dirflg", value: "d"),
            ]
            if let url = components?.url { return url }
        }
        if let lat = entry.latitude, let lon = entry.longitude {
            var components = URLComponents(string: "https://maps.apple.com/")
            components?.queryItems = [
                URLQueryItem(name: "ll", value: "\(lat),\(lon)"),
                URLQueryItem(name: "dirflg", value: "d"),
            ]
            return components?.url
        }
        return nil
    }
}
