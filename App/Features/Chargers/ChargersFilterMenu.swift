//
//  ChargersFilterMenu.swift
//  ExpresScan
//
//  Wave 6 / Slice I — toolbar filter menu for the Chargers tab.
//  One Picker (Online status: All / Online / Offline). The Type
//  filter from earlier plan drafts was retired with the iOS-Chargers-
//  only scope — no app devices in this list, no need to discriminate.
//

import SwiftUI

struct ChargersFilterMenu: View {

    @Binding var filter: ChargerListViewModel.OnlineStatusFilter

    var body: some View {
        Menu {
            Picker("Online status", selection: $filter) {
                ForEach(ChargerListViewModel.OnlineStatusFilter.allCases) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Filter", systemImage: filterIcon)
        }
        .accessibilityLabel("Filter chargers, current: \(filter.rawValue)")
    }

    /// Glyph hints at the active filter without needing to expand
    /// the menu.
    private var filterIcon: String {
        switch filter {
        case .all:    return "line.3.horizontal.decrease.circle"
        case .online: return "checkmark.circle"
        }
    }
}
