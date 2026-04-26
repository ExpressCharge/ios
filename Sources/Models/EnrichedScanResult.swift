//
//  EnrichedScanResult.swift
//  Models
//
//  Mirrors the TS `EnrichedScanResult` interface from `20-contracts.md`.
//  Returned from `POST /api/devices/scan-result` and
//  `GET /api/devices/scan-result/{pairingCode}`.
//

import Foundation

/// Enriched scan result returned to the phone after a successful scan.
///
/// All date fields are kept as raw ISO-8601 strings — the iOS app handles
/// display formatting separately (per `50-ios.md`).
public struct EnrichedScanResult: Codable, Sendable, Equatable {
    /// Always `true` on a successful response. Decoded from the literal
    /// JSON `true`. Kept as `Bool` for forward compat (some endpoints in
    /// related codebases return an `ok: false` envelope).
    public let ok: Bool
    public let found: Bool
    public let pairingCode: String
    /// Hex uppercase, matches `steveOcppIdTag` storage on the backend.
    public let idTag: String
    public let resolvedAtIso: String
    public let tag: TagInfo?
    public let customer: CustomerInfo?
    public let subscription: SubscriptionInfo?

    public init(
        ok: Bool,
        found: Bool,
        pairingCode: String,
        idTag: String,
        resolvedAtIso: String,
        tag: TagInfo?,
        customer: CustomerInfo?,
        subscription: SubscriptionInfo?
    ) {
        self.ok = ok
        self.found = found
        self.pairingCode = pairingCode
        self.idTag = idTag
        self.resolvedAtIso = resolvedAtIso
        self.tag = tag
        self.customer = customer
        self.subscription = subscription
    }

    public struct TagInfo: Codable, Sendable, Equatable {
        public let displayName: String?
        /// e.g. `"ev_card"`, `"phone_nfc"`. Kept as `String` since the
        /// vocabulary lives entirely on the backend.
        public let tagType: String

        public init(displayName: String?, tagType: String) {
            self.displayName = displayName
            self.tagType = tagType
        }
    }

    public struct CustomerInfo: Codable, Sendable, Equatable {
        public let displayName: String?
        public let slug: String?

        public init(displayName: String?, slug: String?) {
            self.displayName = displayName
            self.slug = slug
        }
    }

    public struct SubscriptionInfo: Codable, Sendable, Equatable {
        public let planLabel: String?
        public let status: SubscriptionStatus?
        public let currentPeriodEndIso: String?
        public let billingTier: BillingTier?

        public init(
            planLabel: String?,
            status: SubscriptionStatus?,
            currentPeriodEndIso: String?,
            billingTier: BillingTier?
        ) {
            self.planLabel = planLabel
            self.status = status
            self.currentPeriodEndIso = currentPeriodEndIso
            self.billingTier = billingTier
        }
    }
}
