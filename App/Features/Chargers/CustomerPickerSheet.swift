//
//  CustomerPickerSheet.swift
//  ExpresScan
//
//  Wave 6 / Slice S — the .sheet-presented customer picker invoked when
//  starting an unreserved charger. Replaces `TagPickerSheet`. Native
//  `List` + `.searchable` + `.presentationDetents([.medium, .large])`.
//  Each row is a customer (the server pre-resolves the parent OCPP tag at
//  Start time), so the sheet is a flat list — no per-customer grouping.
//

import SwiftUI

struct CustomerPickerSheet: View {

    let customers: [CustomerOption]
    let onPick: (CustomerOption) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    var body: some View {
        NavigationStack {
            list
                .navigationTitle("Pick a customer")
                .navigationBarTitleDisplayMode(.inline)
                .expressBackground()
                .searchable(
                    text: $query,
                    prompt: "Search customers"
                )
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
        if customers.isEmpty {
            ContentUnavailableView(
                "No customers available",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("Add a customer in the web admin to start charging.")
            )
        } else {
            List {
                ForEach(filtered) { customer in
                    Button {
                        onPick(customer)
                        dismiss()
                    } label: {
                        row(customer)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private func row(_ customer: CustomerOption) -> some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(customer.displayName)
                    .font(.body.weight(.medium))
                if let secondary = secondaryLine(for: customer) {
                    Text(secondary)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if customer.isOwn {
                Text("You")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(ColorPalette.muted)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Email when distinct from the displayName; otherwise the
    /// (mono-spaced) `lagoCustomerExternalId` so the operator has a stable
    /// disambiguator for same-named customers.
    private func secondaryLine(for customer: CustomerOption) -> String? {
        if let email = customer.email, !email.isEmpty,
           email != customer.displayName {
            return email
        }
        return customer.lagoCustomerExternalId
    }

    private var filtered: [CustomerOption] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return customers }
        return customers.filter { c in
            c.displayName.lowercased().contains(q)
                || (c.email?.lowercased().contains(q) ?? false)
                || c.lagoCustomerExternalId.lowercased().contains(q)
        }
    }
}
