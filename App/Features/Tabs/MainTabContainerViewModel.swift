//
//  MainTabContainerViewModel.swift
//  ExpresScan
//
//  Wave 6 / Slice F. Capability-derived shell decision.
//
//  Given the device's capability set, decide which top-level shell to
//  render: a lone Scan view, a lone Chargers view, a two-tab `TabView`,
//  or a chrome-stripped `KioskShell` wrapping the lone view.
//
//  The legality table lives in `Capabilities.isLegalSet(_:)`. This VM
//  simply reads the set and maps it to an enum value the SwiftUI
//  `MainTabContainer` view switches on.
//

import Foundation
import Observation

import Capabilities
import Models

/// Top-level shell decision for the `.ready` route. Derived purely from
/// the current capability set — no networking, no side effects.
@MainActor
@Observable
public final class MainTabContainerViewModel {

    /// Which shell the SwiftUI view should render.
    public enum Shell: Equatable, Sendable {
        /// Lone Scan view as root (caps = `{scanner}`).
        case loneScan
        /// Lone Chargers view as root (caps = `{user}`).
        case loneChargers
        /// Two-tab native `TabView` (caps ⊇ `{scanner, user}`).
        case tabs
        /// Kiosk-wrapped Scan view (caps ⊇ `{scanner, kiosk}`).
        case kioskScan
        /// Kiosk-wrapped Chargers view (caps ⊇ `{user, kiosk}`).
        case kioskChargers
    }

    public var capabilities: Set<DeviceCapability>

    public init(capabilities: Set<DeviceCapability>) {
        self.capabilities = capabilities
    }

    /// The shell to render for the current `capabilities`. Crashes only
    /// on an illegal set (caller must pre-validate via `isLegalSet`).
    public var shell: Shell {
        let kiosk = capabilities.contains(.kiosk)
        let scanner = capabilities.contains(.scanner)
        let user = capabilities.contains(.user)

        if kiosk {
            // Kiosk legality: exactly one of {scanner, user}.
            if scanner { return .kioskScan }
            if user    { return .kioskChargers }
            // Illegal — fall through to a sane default rather than crash.
            return .loneScan
        }
        if scanner && user { return .tabs }
        if user            { return .loneChargers }
        // Default: scanner-only (or unknown) → lone scan view.
        return .loneScan
    }

    /// Whether the bottom tab bar should be drawn — visible iff the
    /// device has both `.scanner` AND `.user`.
    public var tabBarVisible: Bool {
        DeviceCapability.tabBarVisible(capabilities)
    }

    /// Whether the Settings toolbar entry should appear. Hidden under
    /// kiosk, shown otherwise.
    public var settingsMenuVisible: Bool {
        !DeviceCapability.isKiosk(capabilities)
    }
}
