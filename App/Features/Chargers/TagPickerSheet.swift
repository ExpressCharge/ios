//
//  TagPickerSheet.swift
//  ExpresScan
//
//  Wave 6 / Slice J — the .sheet-presented tag picker invoked when
//  starting an unreserved charger. Native `List` + `.searchable` +
//  `.presentationDetents([.medium, .large])`. Sectioned by customer
//  name; tap selects and dismisses.
//

import SwiftUI

struct TagPickerSheet: View {

    let tags: [IdTagOption]
    let onPick: (IdTagOption) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    var body: some View {
        NavigationStack {
            list
                .navigationTitle("Pick a tag")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: "Search tags or customers")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var list: some View {
        if tags.isEmpty {
            ContentUnavailableView(
                "No tags available",
                systemImage: "tag",
                description: Text("Add a customer tag in the web admin to start charging.")
            )
        } else {
            List {
                ForEach(groupedSections, id: \.key) { section in
                    Section(section.key) {
                        ForEach(section.tags) { tag in
                            Button {
                                onPick(tag)
                                dismiss()
                            } label: {
                                row(tag)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private func row(_ tag: IdTagOption) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tag.idTag)
                .font(.body.monospaced())
            if let name = tag.customerName, !name.isEmpty {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private struct GroupedSection {
        let key: String
        let tags: [IdTagOption]
    }

    private var filtered: [IdTagOption] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return tags }
        return tags.filter {
            $0.idTag.lowercased().contains(q)
                || ($0.customerName?.lowercased().contains(q) ?? false)
        }
    }

    private var groupedSections: [GroupedSection] {
        // Stable group order: first appearance of each customer in the
        // (already-recency-sorted) list wins. Untitled rows go to
        // "Other".
        var order: [String] = []
        var buckets: [String: [IdTagOption]] = [:]
        for tag in filtered {
            let key = tag.customerName?.isEmpty == false
                ? tag.customerName!
                : "Other"
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(tag)
        }
        return order.map { GroupedSection(key: $0, tags: buckets[$0] ?? []) }
    }
}
