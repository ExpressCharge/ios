//
//  Capabilities.swift
//  Capabilities
//
//  Pure-Swift derivation + legality helpers built on top of the
//  `DeviceCapability` enum from `Models`. Mirrors the TS-side
//  `capability-metadata.ts` and `validateCapabilitySet` helpers.
//
//  No UIKit / SwiftUI / CoreNFC imports here — this module is consumed by
//  pure-Swift services (`DeviceSync`, `DeviceStateCoordinator`) and by
//  SwiftUI view code in the App target alike.
//

import Foundation
import Models

// MARK: - Derivation + legality

extension DeviceCapability {

    /// Whether this set has at least one of the elements that gates the
    /// lone "main" screen of the app — `.scanner`, `.user`, or `.kiosk`.
    public var isAppCanonicalCapability: Bool {
        switch self {
        case .scanner, .user, .kiosk: return true
        case .charger: return false
        }
    }

    /// `true` iff the capability set is legal:
    ///
    /// - When `.kiosk ∈ caps`, exactly one of `{.scanner, .user}` must
    ///   also be in `caps`. (Kiosk is "single-purpose appliance" mode.)
    /// - Otherwise any non-empty subset is legal at this level.
    public static func isLegalSet(_ caps: Set<DeviceCapability>) -> Bool {
        if caps.contains(.kiosk) {
            let pair: Set<DeviceCapability> = [.scanner, .user]
            return caps.intersection(pair).count == 1
        }
        return true
    }

    /// `true` iff `caps` contains `.user` — which gates the Chargers tab.
    public static func canSeeChargersTab(_ caps: Set<DeviceCapability>) -> Bool {
        caps.contains(.user)
    }

    /// `true` iff `caps` contains `.scanner`.
    public static func canScan(_ caps: Set<DeviceCapability>) -> Bool {
        caps.contains(.scanner)
    }

    /// `true` iff `caps` contains `.kiosk`.
    public static func isKiosk(_ caps: Set<DeviceCapability>) -> Bool {
        caps.contains(.kiosk)
    }

    /// Whether the bottom tab bar is visible — visible iff the device has
    /// **both** `.scanner` and `.user`. A single-capability device has no
    /// tab bar (just the one screen).
    public static func tabBarVisible(_ caps: Set<DeviceCapability>) -> Bool {
        caps.contains(.scanner) && caps.contains(.user)
    }
}

// MARK: - CapabilityMetadata

/// Friendly metadata for a capability — used by the registration picker
/// (Slice H) and the web-admin parity panel. The TS-side mirror lives in
/// `expresscharge/src/lib/devices/capability-metadata.ts`.
public struct CapabilityMetadata: Sendable, Equatable {
    public let key: DeviceCapability
    public let displayName: String
    public let description: String
    public let sfSymbol: String

    public init(
        key: DeviceCapability,
        displayName: String,
        description: String,
        sfSymbol: String
    ) {
        self.key = key
        self.displayName = displayName
        self.description = description
        self.sfSymbol = sfSymbol
    }

    /// All capabilities, in canonical declaration order.
    public static let all: [CapabilityMetadata] = [
        CapabilityMetadata(
            key: .scanner,
            displayName: "NFC scanner",
            description: "Use this device to read NFC chargecards",
            sfSymbol: "nfc"
        ),
        CapabilityMetadata(
            key: .charger,
            displayName: "EV charger",
            description: "This device is a charging station",
            sfSymbol: "bolt.car.fill"
        ),
        CapabilityMetadata(
            key: .user,
            displayName: "Use chargers",
            description: "List chargers, start/stop, see sessions, cancel reservations",
            sfSymbol: "bolt.fill"
        ),
        CapabilityMetadata(
            key: .kiosk,
            displayName: "Kiosk mode",
            description: "Single-purpose appliance, no chrome / no settings",
            sfSymbol: "lock.display"
        ),
    ]

    /// Capabilities offered to the iOS registration picker. Apps can never
    /// be chargers, so `.charger` is excluded.
    public static let registrationOptions: [CapabilityMetadata] = all.filter {
        $0.key != .charger
    }

    /// Lookup by capability key. Crashes only if `all` is missing a key
    /// for `cap`, which is statically impossible since `all` is hand-built
    /// to cover every case.
    public static func metadata(for cap: DeviceCapability) -> CapabilityMetadata {
        guard let m = all.first(where: { $0.key == cap }) else {
            fatalError("CapabilityMetadata.all is missing entry for \(cap)")
        }
        return m
    }
}
