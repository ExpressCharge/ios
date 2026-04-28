//
//  SyncRequest.swift
//  DeviceSync
//
//  Body of `POST /api/devices/me/state/sync`. Mirrors the
//  `SyncRequest` TypeScript shape in the plan's "Sync envelope" section.
//

import Foundation

public struct SyncRequest: Sendable, Equatable, Codable {

    /// Settings the client has touched locally and wants merged. Server
    /// applies LWW per `key` against its own row (clamping `updatedAt`
    /// to ≤ now+5s).
    public var pendingSettings: [PendingSetting]
    public var diagnostics: Diagnostics

    public init(pendingSettings: [PendingSetting], diagnostics: Diagnostics) {
        self.pendingSettings = pendingSettings
        self.diagnostics = diagnostics
    }

    public struct PendingSetting: Sendable, Equatable, Codable {
        public var key: String
        public var value: AnyCodableJSON
        public var updatedAt: String  // ISO-8601 string (server clamps)

        public init(key: String, value: AnyCodableJSON, updatedAt: String) {
            self.key = key
            self.value = value
            self.updatedAt = updatedAt
        }
    }

    /// Strict allow-list of fields. The server snapshot-tests that no
    /// other keys are accepted.
    public struct Diagnostics: Sendable, Equatable, Codable {
        public var appVersion: String
        public var osVersion: String
        public var model: String
        public var pushPermission: PushPermission
        public var nfcAvailable: Bool
        public var pendingUploads: Int
        public var reconnectCount: Int

        public enum PushPermission: String, Sendable, Equatable, Codable {
            case authorized
            case denied
            case notDetermined
            case provisional
        }

        public init(
            appVersion: String,
            osVersion: String,
            model: String,
            pushPermission: PushPermission,
            nfcAvailable: Bool,
            pendingUploads: Int,
            reconnectCount: Int
        ) {
            self.appVersion = appVersion
            self.osVersion = osVersion
            self.model = model
            self.pushPermission = pushPermission
            self.nfcAvailable = nfcAvailable
            self.pendingUploads = pendingUploads
            self.reconnectCount = reconnectCount
        }
    }
}
