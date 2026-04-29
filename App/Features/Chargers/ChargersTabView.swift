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

import SwiftUI

public struct ChargersTabView: View {

    @Environment(\.app) private var app
    @State private var viewModel: ChargerListViewModel?
    @State private var pushedEntry: ChargerListEntry?
    @State private var hasAutoPushed: Bool = false

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
        }
        .onChange(of: viewModel?.displayEntries ?? []) { _, newValue in
            maybeAutoPush(newValue)
        }
    }

    @ViewBuilder
    private func content(vm: ChargerListViewModel) -> some View {
        @Bindable var bound = vm

        switch vm.loadState {
        case .idle, .loading where vm.entries.isEmpty:
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
                    ForEach(vm.displayEntries) { entry in
                        Button { pushedEntry = entry } label: {
                            ChargerListRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(
                            top: 4, leading: 16,
                            bottom: 4, trailing: 16
                        ))
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
