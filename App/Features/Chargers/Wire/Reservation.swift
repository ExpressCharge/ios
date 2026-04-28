//
//  Reservation.swift
//  ExpresScan
//
//  Wave 6 / Slice J — wire-shape mirror for the
//  `GET /api/admin/devices/{chargerId}/reservations` response. Backend
//  source: `expressync/routes/api/admin/devices/[deviceId]/reservations.ts`.
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
    public let isBlackout: Bool
    public let idTag: String?
    public let isCancelable: Bool

    public var id: String { reservationId }

    public init(
        reservationId: String,
        startsAt: Date,
        endsAt: Date,
        customerLabel: String?,
        isBlackout: Bool,
        idTag: String?,
        isCancelable: Bool
    ) {
        self.reservationId = reservationId
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.customerLabel = customerLabel
        self.isBlackout = isBlackout
        self.idTag = idTag
        self.isCancelable = isCancelable
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
