//
//  IdTagOption.swift
//  ExpresScan
//
//  // DEPRECATED Slice S — superseded by `CustomerOption`. The iOS app no
//  // longer calls `/tags`. Kept compiling for one rolling-deploy window
//  // so any straggler references (tests, fixtures) still resolve.
//
//  Wave 6 / Slice J — wire-shape mirror for the
//  `GET /api/admin/devices/{chargerId}/tags` response. Backend source:
//  `expressync/routes/api/admin/devices/[deviceId]/tags.ts`.
//

import Foundation

/// One row in the Tag Picker sheet. The server pre-sorts by recency, so
/// the iOS picker can render in array order without extra logic. We do
/// group by `customerName` for the section headers though.
public struct IdTagOption: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let idTag: String
    public let tagPk: Int
    public let customerName: String?
    public let customerId: String
    public let isOwn: Bool
    public let lastUsedAt: Date?

    /// `idTag` is unique within the active fleet (StEvE constraint), so
    /// it's a stable Identifiable key.
    public var id: String { idTag }

    public init(
        idTag: String,
        tagPk: Int,
        customerName: String?,
        customerId: String,
        isOwn: Bool,
        lastUsedAt: Date?
    ) {
        self.idTag = idTag
        self.tagPk = tagPk
        self.customerName = customerName
        self.customerId = customerId
        self.isOwn = isOwn
        self.lastUsedAt = lastUsedAt
    }
}

/// Top-level envelope for `GET /tags`.
public struct TagsResponse: Codable, Sendable {
    public let tags: [IdTagOption]
}
