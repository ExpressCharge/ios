//
//  HeartbeatPayload.swift
//  Models
//
//  Body for `POST /api/devices/heartbeat`. The endpoint is technically
//  bodyless (the bearer token is enough), but the iOS app reports a tiny
//  payload so the server can opportunistically refresh `app_version` /
//  `os_version` rows without a separate endpoint.
//

import Foundation

/// Optional heartbeat payload. All fields are nilable so the simplest
/// foreground heartbeat can send `{}` or omit the body entirely.
public struct HeartbeatPayload: Codable, Sendable, Equatable {
    public let appVersion: String?
    public let osVersion: String?

    public init(appVersion: String? = nil, osVersion: String? = nil) {
        self.appVersion = appVersion
        self.osVersion = osVersion
    }
}

/// Body for `PUT /api/devices/{deviceId}/push-token`.
public struct PushTokenUpdateRequest: Codable, Sendable, Equatable {
    public let pushToken: String
    public let apnsEnvironment: ApnsEnvironment

    public init(pushToken: String, apnsEnvironment: ApnsEnvironment) {
        self.pushToken = pushToken
        self.apnsEnvironment = apnsEnvironment
    }
}

/// Body for `POST /api/devices/scan-result`. See `20-contracts.md` for the
/// HMAC computation that produces `nonce`.
public struct ScanResultRequest: Codable, Sendable, Equatable {
    /// Hex uppercase.
    public let idTag: String
    public let pairingCode: String
    /// Unix seconds, ±60 s of server clock.
    public let ts: Int64
    /// Lowercase hex HMAC-SHA256 over
    /// `"scan-result/v1|" + idTag + "|" + pairingCode + "|" + deviceId + "|" + ts`.
    public let nonce: String

    public init(idTag: String, pairingCode: String, ts: Int64, nonce: String) {
        self.idTag = idTag
        self.pairingCode = pairingCode
        self.ts = ts
        self.nonce = nonce
    }
}
