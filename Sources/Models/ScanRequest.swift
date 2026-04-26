//
//  ScanRequest.swift
//  Models
//
//  Mirrors the TS `DeviceScanRequestedPayload` interface from
//  `20-contracts.md`. Sent in the `device.scan.requested` event bus payload
//  AND inside the APNs push payload.
//

import Foundation

/// A scan request from the server: the phone should arm an NFC session
/// against this `pairingCode` until `expiresAt`.
public struct ScanRequest: Codable, Sendable, Equatable {
    public let deviceId: String
    public let pairingCode: String
    public let purpose: ScanPurpose
    public let expiresAtIso: String
    public let expiresAtEpochMs: Int64
    /// `nil` = system-initiated.
    public let requestedByUserId: String?
    /// Free-text shown in app, e.g. `"Front desk"`.
    public let hintLabel: String?

    public init(
        deviceId: String,
        pairingCode: String,
        purpose: ScanPurpose,
        expiresAtIso: String,
        expiresAtEpochMs: Int64,
        requestedByUserId: String?,
        hintLabel: String?
    ) {
        self.deviceId = deviceId
        self.pairingCode = pairingCode
        self.purpose = purpose
        self.expiresAtIso = expiresAtIso
        self.expiresAtEpochMs = expiresAtEpochMs
        self.requestedByUserId = requestedByUserId
        self.hintLabel = hintLabel
    }
}
