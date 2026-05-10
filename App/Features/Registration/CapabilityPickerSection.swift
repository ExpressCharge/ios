//
//  CapabilityPickerSection.swift
//  ExpresScan
//
//  SwiftUI section for the registration screen — multi-select toggle
//  list over the three app-eligible capabilities (`scanner`, `user`,
//  `kiosk`). `charger` is intentionally absent: apps cannot self-register
//  as chargers.
//
//  Spec: `50-ios.md` § "Registration capability picker" (Wave 6 / Slice H).
//

import Capabilities
import Models
import SwiftUI

/// Section component rendered inside `RegistrationView`'s `Form`. Owns
/// no state; the parent passes a `Binding<Set<DeviceCapability>>`.
public struct CapabilityPickerSection: View {

    @Binding var selected: Set<DeviceCapability>

    /// Owner role of the account this device is being registered under.
    /// `.managed` is hidden when the role is `customer` — managed-device
    /// admin-locate is an admin-fleet feature, not a consumer feature.
    let isCustomerOwner: Bool

    public init(
        selected: Binding<Set<DeviceCapability>>,
        isCustomerOwner: Bool = false
    ) {
        self._selected = selected
        self.isCustomerOwner = isCustomerOwner
    }

    /// Visible options for this render. Filters `.managed` out for
    /// customer-owned registrations; otherwise mirrors
    /// `CapabilityMetadata.registrationOptions`.
    private var visibleOptions: [CapabilityMetadata] {
        CapabilityMetadata.registrationOptions.filter { meta in
            if meta.key == .managed && isCustomerOwner { return false }
            return true
        }
    }

    public var body: some View {
        Section {
            ForEach(visibleOptions, id: \.key) { meta in
                row(for: meta)
                if meta.key == .kiosk, !isLegal {
                    illegalKioskFooter
                }
                if meta.key == .managed {
                    managedFooter
                }
            }
        } header: {
            Text("What will this iPhone do?")
        } footer: {
            Text("Pick at least one. You can change these later from the web admin.")
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(for meta: CapabilityMetadata) -> some View {
        Toggle(isOn: binding(for: meta.key)) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: meta.sfSymbol)
                    .font(.title3)
                    .foregroundStyle(ColorPalette.primaryCyan)
                    .frame(width: 28, alignment: .center)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(meta.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(meta.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(ColorPalette.primaryCyan)
        .accessibilityIdentifier("capabilityToggle_\(meta.key.rawValue)")
    }

    private var illegalKioskFooter: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ColorPalette.destructiveRose)
                .accessibilityHidden(true)
            Text("Kiosk pairs with only one base capability. Pick one of Scanner or Use chargers.")
                .font(.caption)
                .foregroundStyle(ColorPalette.destructiveRose)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("capabilityPicker_kioskIllegalError")
    }

    private var managedFooter: some View {
        Text("Allows your admin to request this device's location.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("capabilityPicker_managedFooter")
    }

    // MARK: - Binding helpers

    private func binding(for cap: DeviceCapability) -> Binding<Bool> {
        Binding(
            get: { selected.contains(cap) },
            set: { isOn in
                if isOn {
                    selected.insert(cap)
                } else {
                    selected.remove(cap)
                }
            }
        )
    }

    private var isLegal: Bool {
        DeviceCapability.isLegalSet(selected)
    }
}
