//
//  ChargersTabView.swift
//  ExpresScan
//
//  Wave 6 / Slice I — the Chargers tab content. Parent (`MainTabContainer`)
//  already owns the `NavigationStack` and toolbar Settings menu, so this
//  view only contributes the title + filter Menu + list.
//
//  States:
//   - Loading: `ProgressView` while the first fetch is in flight.
//   - Error:   `ContentUnavailableView` with a Retry button.
//   - Empty:   `ContentUnavailableView` ("No chargers yet").
//   - Loaded:  native `List` of `ChargerListRow` with `.refreshable`
//              pull-to-refresh.
//

import SwiftUI

public struct ChargersTabView: View {

    @Environment(\.app) private var app
    @State private var viewModel: ChargerListViewModel?

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
        .task {
            if viewModel == nil {
                let vm = ChargerListViewModel(api: app.api)
                self.viewModel = vm
                await vm.refresh()
            }
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
                        NavigationLink(value: entry) {
                            ChargerListRow(entry: entry)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationDestination(for: ChargerListEntry.self) { entry in
            // Slice J-iOS owns the real charger detail; this is the
            // wired-up placeholder until then.
            ChargerDetailPlaceholderView(entry: entry)
        }
        .refreshable { await vm.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ChargersFilterMenu(filter: filterBinding)
            }
        }
    }
}

/// Placeholder destination until Slice J-iOS lands the real detail UI.
/// Renders enough chrome to confirm navigation works without
/// pre-empting J-iOS's design.
struct ChargerDetailPlaceholderView: View {
    let entry: ChargerListEntry

    var body: some View {
        ContentUnavailableView(
            label: {
                Label(entry.label, systemImage: "ev.charger")
            },
            description: {
                Text("Charger detail coming soon.\nID: \(entry.chargerId)")
            }
        )
        .navigationTitle(entry.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}
