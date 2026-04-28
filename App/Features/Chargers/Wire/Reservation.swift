//
//  Reservation.swift
//  ExpresScan
//
//  Wave 6 / Slice J — wire-shape mirror for the
//  `GET /api/admin/devices/{chargerId}/reservations` response. Backend
//  source: `expresscharge/routes/api/admin/devices/[deviceId]/reservations.ts`.
//
//  `customerLabel == nil` is meaningful — the server uses null to flag
//  admin-set blackout periods. The iOS row must show "Blackout" in that
//  case (don't try to invent a label).
//

import Foundation

/// One upcoming reservation (or admin blackout) on a charger.
public struct Reservation: Codable, Sendable, Equatable, Identifiable {
    public let reservationId: String
    public let startsAt: Date
    public let endsAt: Date
    /// `nil` ⇔ blackout (or unmapped tag). Render as "Blackout".
    public let customerLabel: String?
    /// Slice S — Lago customer `external_id`. Path A start uses this to
    /// resolve the customer (and thus the `OCPP-{externalId}` parent tag)
    /// without a separate picker round-trip. `nil` for blackouts.
    public let lagoCustomerExternalId: String?
    public let isBlackout: Bool
    /// Legacy idTag (Slice J). Decoded as optional; kept during the
    /// rolling-deploy window so older server builds still parse. iOS no
    /// longer renders this — see `customerLabel`.
    public let idTag: String?
    public let isCancelable: Bool

    public var id: String { reservationId }

    public init(
        reservationId: String,
        startsAt: Date,
        endsAt: Date,
        customerLabel: String?,
        lagoCustomerExternalId: String? = nil,
        isBlackout: Bool,
        idTag: String? = nil,
        isCancelable: Bool
    ) {
        self.reservationId = reservationId
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.customerLabel = customerLabel
        self.lagoCustomerExternalId = lagoCustomerExternalId
        self.isBlackout = isBlackout
        self.idTag = idTag
        self.isCancelable = isCancelable
    }

    private enum CodingKeys: String, CodingKey {
        case reservationId, startsAt, endsAt, customerLabel
        case lagoCustomerExternalId, isBlackout, idTag, isCancelable
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.reservationId = try c.decode(String.self, forKey: .reservationId)
        self.startsAt = try c.decode(Date.self, forKey: .startsAt)
        self.endsAt = try c.decode(Date.self, forKey: .endsAt)
        self.customerLabel = try c.decodeIfPresent(String.self, forKey: .customerLabel)
        // Slice S — optional during rolling deploy.
        self.lagoCustomerExternalId = try c.decodeIfPresent(
            String.self, forKey: .lagoCustomerExternalId
        )
        self.isBlackout = try c.decode(Bool.self, forKey: .isBlackout)
        self.idTag = try c.decodeIfPresent(String.self, forKey: .idTag)
        self.isCancelable = try c.decode(Bool.self, forKey: .isCancelable)
    }

    /// `true` when `Date()` falls inside `[startsAt, endsAt)`. Drives the
    /// charger-detail "Reserved" hero state and the auto-tag-binding for
    /// Path A start.
    public func covers(_ date: Date) -> Bool {
        date >= startsAt && date < endsAt
    }
}

/// Top-level envelope for `GET /reservations`.
public struct ReservationsResponse: Codable, Sendable {
    public let reservations: [Reservation]
}
