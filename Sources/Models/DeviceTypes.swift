//
//  DeviceTypes.swift
//  Models
//
//  Mirrors the shared TS enums in `expresscharge/src/lib/types/devices.ts`.
//  See `docs/plan/20-contracts.md` for the canonical definitions.
//

import Foundation

/// The kind of device. Mirrors the TS `DEVICE_KINDS` tuple — keep wire values
/// in sync.
///
/// `tabletNFC` is reserved for future iPadOS support — only iPhones register
/// today, but the kind is wired through types so adding tablet registration
/// later doesn't require a contract sweep.
public enum DeviceKind: String, Codable, Sendable, CaseIterable {
    case phoneNFC = "phone_nfc"
    case tabletNFC = "tablet_nfc"
    case laptopNFC = "laptop_nfc"
}

/// What a device can do. Mirrors `DEVICE_CAPABILITIES`.
///
/// - `scanner` (was `tap`): device has an NFC tap reader.
/// - `charger` (was `ev`): device IS an EV charging station. Auto-managed
///   on charger rows; never editable; never present on app rows.
/// - `user`: app device unlocks the Chargers tab (list, charger detail,
///   start/stop, cancel reservations).
/// - `kiosk`: app device runs in single-screen appliance mode. Legal only
///   when the set contains exactly one of `{scanner, user}`.
public enum DeviceCapability: String, Codable, Sendable, CaseIterable {
    case scanner
    case charger
    case user
    case kiosk
}

/// Capabilities the iOS registration picker may offer. Apps can never be
/// chargers, so `charger` is excluded from the picker.
public extension DeviceCapability {
    static let appRegistrationOptions: [DeviceCapability] = [
        .scanner, .user, .kiosk,
    ]
}

/// Why a scan is happening. Mirrors `SCAN_PURPOSES`.
public enum ScanPurpose: String, Codable, Sendable, CaseIterable {
    case adminLink = "admin-link"
    case customerLink = "customer-link"
    case login
    case viewCard = "view-card"
}

/// Whether a tap target is a charger (legacy) or a phone/laptop device.
public enum PairableType: String, Codable, Sendable {
    case device
    case charger
}

/// Lifecycle status of a subscription, used by `EnrichedScanResult`.
public enum SubscriptionStatus: String, Codable, Sendable {
    case active
    case pending
    case terminated
    case canceled
}

/// Billing tier for a subscription, used by `EnrichedScanResult`.
public enum BillingTier: String, Codable, Sendable {
    case standard
    case comped
}

/// APNs environment a device's push token was minted against.
public enum ApnsEnvironment: String, Codable, Sendable {
    case sandbox
    case production
}
