//
//  DeviceSummary.swift
//  Models
//
//  Mirrors the TS `DeviceSummary` interface from `20-contracts.md`.
//

import Foundation

/// Summary of a device as returned by the admin listing endpoint.
public struct DeviceSummary: Codable, Sendable, Equatable {
    public let deviceId: String
    public let kind: DeviceKind
    public let label: String
    public let capabilities: [DeviceCapability]
    public let ownerUserId: String?
    public let platform: String?
    public let model: String?
    public let appVersion: String?
    public let lastSeenAtIso: String?
    public let isOnline: Bool
    public let registeredAtIso: String

    public init(
        deviceId: String,
        kind: DeviceKind,
        label: String,
        capabilities: [DeviceCapability],
        ownerUserId: String?,
        platform: String?,
        model: String?,
        appVersion: String?,
        lastSeenAtIso: String?,
        isOnline: Bool,
        registeredAtIso: String
    ) {
        self.deviceId = deviceId
        self.kind = kind
        self.label = label
        self.capabilities = capabilities
        self.ownerUserId = ownerUserId
        self.platform = platform
        self.model = model
        self.appVersion = appVersion
        self.lastSeenAtIso = lastSeenAtIso
        self.isOnline = isOnline
        self.registeredAtIso = registeredAtIso
    }
}

/// Mirrors TS `TapTargetEntry`. Returned from `GET /api/auth/scan-tap-targets`.
public struct TapTargetEntry: Codable, Sendable, Equatable {
    /// For phones: device UUID; for chargers: chargeBoxId.
    public let deviceId: String
    public let pairableType: PairableType
    /// The string `"charger"` or one of the `DeviceKind` raw values. Kept
    /// as `String` because it widens beyond `DeviceKind`.
    public let kind: String
    public let label: String
    public let capabilities: [DeviceCapability]
    public let isOnline: Bool
    /// Hint to frontend for picker grouping.
    public let isOwnDevice: Bool?

    public init(
        deviceId: String,
        pairableType: PairableType,
        kind: String,
        label: String,
        capabilities: [DeviceCapability],
        isOnline: Bool,
        isOwnDevice: Bool? = nil
    ) {
        self.deviceId = deviceId
        self.pairableType = pairableType
        self.kind = kind
        self.label = label
        self.capabilities = capabilities
        self.isOnline = isOnline
        self.isOwnDevice = isOwnDevice
    }
}
