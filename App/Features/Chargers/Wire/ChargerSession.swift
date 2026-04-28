//
//  ChargerSession.swift
//  ExpresScan
//
//  Wave 6 / Slice J — wire-shape mirror for the
//  `GET /api/admin/devices/{chargerId}/session` response. Backend source
//  of truth: `expressync/routes/api/admin/devices/[deviceId]/session.ts`.
//
//  The server wraps the active session in an envelope so Swift's decoder
//  always finds a top-level `session` key — even when the charger is
//  currently idle (`session: null`). Don't unwrap on the wire side; let
//  callers see the optional and decide.
//

import Foundation

/// One row in the live-session feed for a single charger. All telemetry
/// fields are optional — StEvE can lag behind iOS's polling cadence and
/// the customer-name lookup may miss for blackout-style synthetic tags.
public struct ChargerSession: Codable, Sendable, Equatable {

    public enum SessionState: String, Codable, Sendable, CaseIterable {
        case idle
        case preparing
        case charging
        case stopping
        case outOfService
    }

    public let chargerId: String
    public let sessionId: String?
    public let state: SessionState
    public let startedAt: Date?
    public let idTag: String?
    public let customerName: String?
    public let kwh: Double?
    public let kw: Double?
    public let elapsedSec: Int?
    public let connectorId: Int?

    public init(
        chargerId: String,
        sessionId: String? = nil,
        state: SessionState,
        startedAt: Date? = nil,
        idTag: String? = nil,
        customerName: String? = nil,
        kwh: Double? = nil,
        kw: Double? = nil,
        elapsedSec: Int? = nil,
        connectorId: Int? = nil
    ) {
        self.chargerId = chargerId
        self.sessionId = sessionId
        self.state = state
        self.startedAt = startedAt
        self.idTag = idTag
        self.customerName = customerName
        self.kwh = kwh
        self.kw = kw
        self.elapsedSec = elapsedSec
        self.connectorId = connectorId
    }
}

/// Top-level envelope for `GET /session`. `session` is nullable; the
/// other two fields always come back so iOS can render the hero state
/// even when no session is active.
public struct ChargerSessionResponse: Codable, Sendable {
    public let session: ChargerSession?
    public let state: ChargerSession.SessionState
    public let chargerId: String
}
