//
//  ChargersTabView.swift
//  ExpresScan
//
//  Wave 6 / Slice I — the Chargers tab content. Parent (`MainTabContainer`)
//  owns the `NavigationStack` and toolbar Settings menu, so this view
//  only contributes the title + filter Menu + list.
//
//  Single-charger fast path: the first time the list resolves to
//  exactly one charger, we auto-push its detail screen so the user
//  doesn't have to tap a list of one. Tapping back returns to the
//  list (so users can still see "other" chargers as the fleet grows).
//

import Networking
import SwiftUI

public struct ChargersTabView: View {

    @Environment(\.app) private var app
    @State private var viewModel: ChargerListViewModel?
    @State private var pushedEntry: ChargerListEntry?
    @State private var hasAutoPushed: Bool = false
    /// Deep-link target id stashed when the notification arrives before
    /// the list has loaded — replayed once `displayEntries` populates
    /// (covers cold-launch from a sticker scan).
    @State private var pendingDeepLinkId: String?
    @State private var deepLinkLoading: Bool = false

    public init() {}

    public var body: some View {
        Group {
            if let vm = viewModel {
                content(vm: vm)
            } else {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .navigationTitle("Chargers")
        .navigationBarTitleDisplayMode(.inline)
        .expressBackground()
        .navigationDestination(item: $pushedEntry) { entry in
            ChargerDetailView(entry: entry)
        }
        .task {
            if viewModel == nil {
                let vm = ChargerListViewModel(api: app.api)
                self.viewModel = vm
                await vm.refresh()
            }
            // Track I5 — request location permission lazily on first
            // visit, then start streaming fixes. The view model reads
            // `currentLocation` from `app.locationService` on every
            // render via the binding below.
            app.locationService.requestAuthorization()
            app.locationService.startUpdating()
        }
        .onDisappear {
            // Stop the location indicator when the user leaves the
            // Chargers tab so the system status bar's "in use" arrow
            // accurately reflects what we're doing.
            app.locationService.stopUpdating()
        }
        .onChange(of: app.locationService.currentLocation) { _, newValue in
            viewModel?.currentLocation = newValue
        }
        .onChange(of: viewModel?.displayEntries ?? []) { _, newValue in
            maybeAutoPush(newValue)
            replayPendingDeepLink(newValue)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: AppNotifications.chargerDeepLinkRequested)
        ) { note in
            guard let id = note.userInfo?["chargerId"] as? String else { return }
            handleDeepLink(chargerId: id)
        }
    }

    /// Look up the id in the loaded list and push it. If the list isn't
    /// loaded yet (cold-launch from a sticker), stash the id and let
    /// `replayPendingDeepLink` finish the job once entries arrive. If
    /// the id isn't in the list at all (e.g. permissions or a freshly-
    /// added charger), fall back to a single-charger fetch.
    private func handleDeepLink(chargerId: String) {
        if let match = viewModel?.entries.first(where: { $0.chargerId == chargerId }) {
            pushedEntry = match
            return
        }
        if viewModel?.displayEntries.isEmpty ?? true {
            pendingDeepLinkId = chargerId
            return
        }
        Task { await fetchAndPush(chargerId: chargerId) }
    }

    private func replayPendingDeepLink(_ entries: [ChargerListEntry]) {
        guard let id = pendingDeepLinkId else { return }
        if let match = entries.first(where: { $0.chargerId == id }) {
            pendingDeepLinkId = nil
            pushedEntry = match
            return
        }
        // List loaded but the id isn't there — fetch directly.
        pendingDeepLinkId = nil
        Task { await fetchAndPush(chargerId: id) }
    }

    /// Fallback for a deep-link id that isn't in the cached list (e.g. a
    /// fresh unmanaged charger created server-side after the last list
    /// refresh). Hits `GET /api/devices/{id}` and pushes the result.
    private func fetchAndPush(chargerId: String) async {
        guard !deepLinkLoading else { return }
        deepLinkLoading = true
        defer { deepLinkLoading = false }

        let endpoint = Endpoint(
            path: "/api/devices/\(chargerId)",
            method: .get
        )
        struct SingleChargerResponse: Decodable, Sendable {
            let charger: ChargerListEntry
        }
        do {
            let response: SingleChargerResponse = try await app.api.request(endpoint)
            pushedEntry = response.charger
        } catch {
            // Soft failure — sticker may be wrong / charger removed. Stay
            // on the list; the user can retry by tapping again.
        }
    }

    @ViewBuilder
    private func content(vm: ChargerListViewModel) -> some View {
        @Bindable var bound = vm

        switch vm.loadState {
        case .idle,
            .loading where vm.entries.isEmpty:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .error(let message) where vm.entries.isEmpty:
            ContentUnavailableView(
                label: {
                    Label("Couldn't load chargers", systemImage: "exclamationmark.triangle")
                },
                description: { Text(message) },
                actions: {
                    Button("Try again") { Task { await vm.refresh() } }
                }
            )

        default:
            list(vm: vm, filterBinding: $bound.filter)
        }
    }

    @ViewBuilder
    private func list(
        vm: ChargerListViewModel,
        filterBinding: Binding<ChargerListViewModel.OnlineStatusFilter>
    ) -> some View {
        Group {
            if vm.isEmpty {
                ContentUnavailableView(
                    "No chargers yet",
                    systemImage: "ev.charger",
                    description: Text("Chargers connected via OCPP will appear here.")
                )
            } else {
                List {
                    // Track I5 — proximity-promoted "primary" card. When
                    // the user is within ~150 m of any charger, the
                    // closest one moves into a tall card at the top of
                    // the list. The remaining chargers render as
                    // standard rows below it.
                    if let primary = vm.primaryEntry,
                        let here = vm.currentLocation
                    {
                        Section {
                            Button {
                                pushedEntry = primary
                            } label: {
                                ChargerPrimaryCard(
                                    entry: primary,
                                    distanceMeters: vm.distance(
                                        from: here, to: primary
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(
                                EdgeInsets(
                                    top: 8, leading: 16,
                                    bottom: 12, trailing: 16
                                )
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    ForEach(vm.secondaryEntries) { entry in
                        Button {
                            pushedEntry = entry
                        } label: {
                            ChargerListRow(
                                entry: entry,
                                distanceMeters: vm.currentLocation.flatMap {
                                    vm.distance(from: $0, to: entry)
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(
                            EdgeInsets(
                                top: 4, leading: 16,
                                bottom: 4, trailing: 16
                            )
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .refreshable { await vm.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ChargersFilterMenu(filter: filterBinding)
            }
        }
    }

    /// First time the list resolves to a single charger, push its
    /// detail screen automatically. `hasAutoPushed` latches so backing
    /// out leaves the user on the list, even if a refresh re-evaluates
    /// the same single-entry response.
    private func maybeAutoPush(_ entries: [ChargerListEntry]) {
        guard !hasAutoPushed,
            entries.count == 1,
            let only = entries.first
        else { return }
        pushedEntry = only
        hasAutoPushed = true
    }
}
