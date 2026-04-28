//
//  CustomerOption.swift
//  ExpresScan
//
//  Wave 6 / Slice S — wire-shape mirror for the
//  `GET /api/admin/devices/{chargerId}/customers` response. Backend
//  source: `expresscharge/routes/api/admin/devices/[deviceId]/customers.ts`.
//
//  Replaces `IdTagOption` for the charger-detail picker. The operator now
//  picks a *customer* (by Lago `external_id`); the server resolves the
//  customer's auto-managed parent OCPP tag (`OCPP-{externalId}`) at Start
//  time. Server pre-sorts by recency, so the picker can render in array
//  order without extra logic.
//

import Foundation

/// One row in the Customer Picker sheet.
public struct CustomerOption: Codable, Sendable, Equatable, Identifiable, Hashable {
    /// Lago customer `external_id` — also the suffix of the managed
    /// `OCPP-{externalId}` parent tag.
    public let lagoCustomerExternalId: String
    /// Internal `users.id` (UUID-shaped). Useful for analytics / debug.
    public let userId: String
    /// Server-resolved name → email → userId fallback. Render directly.
    public let displayName: String
    public let name: String?
    public let email: String?
    /// True when the customer matches the calling device's owner (user
    /// surface only — admin callers always see `false`).
    public let isOwn: Bool
    public let lastUsedAt: Date?

    /// `lagoCustomerExternalId` is unique per customer in the live fleet,
    /// so it's a stable Identifiable key.
    public var id: String { lagoCustomerExternalId }

    public init(
        lagoCustomerExternalId: String,
        userId: String,
        displayName: String,
        name: String?,
        email: String?,
        isOwn: Bool,
        lastUsedAt: Date?
    ) {
        self.lagoCustomerExternalId = lagoCustomerExternalId
        self.userId = userId
        self.displayName = displayName
        self.name = name
        self.email = email
        self.isOwn = isOwn
        self.lastUsedAt = lastUsedAt
    }
}

/// Top-level envelope for `GET /customers`.
public struct CustomersResponse: Codable, Sendable {
    public let customers: [CustomerOption]
}
