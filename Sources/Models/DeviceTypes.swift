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
public enum DeviceKind: String, Codable, Sendable, CaseIterable {
    case phoneNFC = "phone_nfc"
    case laptopNFC = "laptop_nfc"
}

/// What a device can do. Mirrors `DEVICE_CAPABILITIES`.
public enum DeviceCapability: String, Codable, Sendable, CaseIterable {
    case tap
    case ev
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
