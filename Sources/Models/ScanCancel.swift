//
//  ScanCancel.swift
//  Models
//
//  Wire shapes for the bidirectional cancel-sync between the iOS
//  active-scan screen and the admin's TapToAddModal:
//
//   - `ScanCancelRequest` — body for `POST /api/devices/scan-cancel`,
//     fired from `ScanCoordinator.cancelActiveScan()` when the user
//     dismisses the active screen.
//
//   - `ScanCancelledPayload` — body of the `event: scan.cancelled`
//     SSE frame the device's `/api/devices/scan-stream` forwards when
//     the admin closes the modal (DELETE `/api/admin/devices/{id}/
//     scan-arm`) or another iOS session cancels first. Drives
//     `ScanCoordinator`'s `scan.cancelled` event handler.
//
//  Both shapes share the same `pairingCode` field so the server
//  matches the cancel against the row keyed
//  `device-scan:{deviceId}:{pairingCode}` regardless of which side
//  initiated.
//

import Foundation

public struct ScanCancelRequest: Codable, Sendable, Equatable {
    public let pairingCode: String

    public init(pairingCode: String) {
        self.pairingCode = pairingCode
    }
}

public struct ScanCancelledPayload: Codable, Sendable, Equatable {
    public let deviceId: String
    public let pairingCode: String
    /// ms since epoch of the cancel.
    public let cancelledAt: Int64
    /// `"admin"` when the cancel came from the TapToAddModal close,
    /// `"device"` when this same iOS bearer (or a parallel iOS
    /// session) POSTed `/api/devices/scan-cancel`.
    public let source: String

    public init(deviceId: String, pairingCode: String, cancelledAt: Int64, source: String) {
        self.deviceId = deviceId
        self.pairingCode = pairingCode
        self.cancelledAt = cancelledAt
        self.source = source
    }
}
