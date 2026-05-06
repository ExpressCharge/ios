//
//  DeviceState.swift
//  DeviceSync
//
//  Codable mirror of the `GET /api/devices/me/state` response envelope.
//  The wire shape is the source of truth — this file matches the spec in
//  `docs/plan/...` and the plan's "Sync envelope" section.
//
//  All wire keys are camelCase already (matches the TS source of truth);
//  no key-decoding strategy is applied.
//

import Foundation
import Models

// MARK: - DeviceState (top-level envelope)

public struct DeviceState: Sendable, Equatable, Codable {

    public var device: DeviceSummary
    public var capabilities: [DeviceCapability]
    public var kioskAllowed: Bool
    public var ownerUser: OwnerUser
    /// Per-key reconciled settings, keyed by setting name (e.g.
    /// `"device.label"`).
    public var settings: [String: DeviceSettingValue]
    /// `nil` when the device does not have the `.scanner` capability.
    public var scanStatus: ScanStatus?
    /// `nil` when the device has no APNs token registered.
    public var pushToken: PushTokenInfo?
    public var connectivity: Connectivity
    /// Server hint that it has no APNs token for this device but the
    /// device last reported notifications as authorized / provisional /
    /// ephemeral. When `true`, the client should call
    /// `registerForRemoteNotifications()` to re-deliver the token.
    /// Optional so older servers that don't emit the field still decode.
    public var needsPushToken: Bool?

    public init(
        device: DeviceSummary,
        capabilities: [DeviceCapability],
        kioskAllowed: Bool,
        ownerUser: OwnerUser,
        settings: [String: DeviceSettingValue],
        scanStatus: ScanStatus?,
        pushToken: PushTokenInfo?,
        connectivity: Connectivity,
        needsPushToken: Bool? = nil
    ) {
        self.device = device
        self.capabilities = capabilities
        self.kioskAllowed = kioskAllowed
        self.ownerUser = ownerUser
        self.settings = settings
        self.scanStatus = scanStatus
        self.pushToken = pushToken
        self.connectivity = connectivity
        self.needsPushToken = needsPushToken
    }

    // MARK: - Nested

    /// Compact summary of the device row itself. Named `DeviceSummary`
    /// locally to match the envelope spec; distinct from the existing
    /// top-level `Models.DeviceSummary` (used by other endpoints).
    public struct DeviceSummary: Sendable, Equatable, Codable {
        public var id: String
        public var label: String
        public var kind: DeviceKind
        public var ownerUserId: String
        public var siteId: String?
        /// ISO-8601 timestamps as strings — no `Date` decoding here so we
        /// don't fight server fractional-seconds variations. Higher
        /// layers parse as needed.
        public var registeredAt: String
        public var lastSeenAt: String

        public init(
            id: String,
            label: String,
            kind: DeviceKind,
            ownerUserId: String,
            siteId: String?,
            registeredAt: String,
            lastSeenAt: String
        ) {
            self.id = id
            self.label = label
            self.kind = kind
            self.ownerUserId = ownerUserId
            self.siteId = siteId
            self.registeredAt = registeredAt
            self.lastSeenAt = lastSeenAt
        }
    }

    public struct OwnerUser: Sendable, Equatable, Codable {
        public var id: String
        public var role: Role
        public var displayName: String

        public enum Role: String, Sendable, Equatable, Codable {
            case admin
            case customer
        }

        public init(id: String, role: Role, displayName: String) {
            self.id = id
            self.role = role
            self.displayName = displayName
        }
    }

    public struct ScanStatus: Sendable, Equatable, Codable {
        public var armed: Bool
        public var pairingCode: String?
        public var expiresAt: String?

        public init(armed: Bool, pairingCode: String?, expiresAt: String?) {
            self.armed = armed
            self.pairingCode = pairingCode
            self.expiresAt = expiresAt
        }
    }

    public struct PushTokenInfo: Sendable, Equatable, Codable {
        /// Last 8 characters of the APNs device token (server never
        /// returns the full token).
        public var last8: String
        public var environment: ApnsEnvironment

        public init(last8: String, environment: ApnsEnvironment) {
            self.last8 = last8
            self.environment = environment
        }
    }

    public struct Connectivity: Sendable, Equatable, Codable {
        public var online: Bool
        public var lastSyncAt: String?
        public var reconnectCount: Int
        public var pendingUploads: Int

        public init(
            online: Bool,
            lastSyncAt: String?,
            reconnectCount: Int,
            pendingUploads: Int
        ) {
            self.online = online
            self.lastSyncAt = lastSyncAt
            self.reconnectCount = reconnectCount
            self.pendingUploads = pendingUploads
        }
    }
}
