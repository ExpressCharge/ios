//
//  ChargerListEntry.swift
//  ExpresScan
//
//  Wave 6 / Slice I — wire-shape mirror for the `GET /api/devices`
//  response. Matches `expressync/routes/api/devices/index.ts`'s
//  `ChargerRowSchema` exactly. Live changes to either side require
//  updating both.
//

import Foundation

/// One charger row from `GET /api/devices`. Decoded straight off the
/// wire — the iOS list view consumes it without further translation.
public struct ChargerListEntry: Codable, Identifiable, Hashable, Sendable {
    public let chargerId: String
    public let label: String
    public let siteName: String?
    public let formFactor: FormFactor
    public let connectorType: ConnectorType?
    public let maxKw: Double?
    public let state: ChargerState
    public let lastSeenAt: Date?

    /// Identifiable conformance — the `chargeBoxId` is unique per
    /// charger and stable across rebuilds.
    public var id: String { chargerId }

    public enum FormFactor: String, Codable, Sendable, CaseIterable {
        case wallbox
        case pulsar
        case commander
        case wallMount = "wall_mount"
        case generic
    }

    public enum ConnectorType: String, Codable, Sendable, CaseIterable {
        case ccs
        case j1772
        case nacs
        case chademo
        case type2
    }

    public enum ChargerState: String, Codable, Sendable, CaseIterable {
        case idle
        case preparing
        case charging
        case reserved
        case outOfService
        case offline

        /// `true` when the charger is contactable and running.
        public var isOnline: Bool {
            switch self {
            case .offline:        return false
            case .idle,
                 .preparing,
                 .charging,
                 .reserved,
                 .outOfService:    return true
            }
        }

        /// User-facing label for the row's online pill.
        public var displayLabel: String {
            switch self {
            case .idle:           return "Idle"
            case .preparing:      return "Plugged in"
            case .charging:       return "Charging"
            case .reserved:       return "Reserved"
            case .outOfService:   return "Out of service"
            case .offline:        return "Offline"
            }
        }
    }
}

/// Top-level response envelope.
public struct ChargersListResponse: Codable, Sendable {
    public let chargers: [ChargerListEntry]
}
