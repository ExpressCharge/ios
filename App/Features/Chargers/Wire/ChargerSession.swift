//
//  ChargerSession.swift
//  ExpresScan
//
//  Wave 6 / Slice J — wire-shape mirror for the
//  `GET /api/admin/devices/{chargerId}/session` response. Backend source
//  of truth: `expresscharge/routes/api/admin/devices/[deviceId]/session.ts`.
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
    /// Whole-amp current draw, derived server-side from `kw` assuming
    /// a 240 V single-phase circuit. Optional on the wire for backward
    /// compatibility with older server builds — when `nil`, the iOS
    /// active card derives it locally.
    public let amps: Int?
    /// Customer's plan max-amp cap (`ev.max_amps` Lago entitlement).
    /// Surfaced so the active card can render `{amps}/{maxAmps} A`
    /// rather than just `{amps} A`. `nil` when the customer has no
    /// active subscription, no plan, or the entitlement is missing.
    public let maxAmps: Int?
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
        amps: Int? = nil,
        maxAmps: Int? = nil,
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
        self.amps = amps
        self.maxAmps = maxAmps
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
