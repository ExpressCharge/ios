//
//  LocationSnapshot.swift
//  DeviceSync
//
//  Wire-shape for the optional `location` field on the sync envelope
//  (Phase 2 / Bundle 2a). Identical client-internal and server-side
//  representation: lat / lon / accuracy-metres / capturedAt. Pure
//  Foundation so it can be referenced from both `DeviceSync` (for the
//  `SyncRequest` body) and the `App/`-target `ManagedLocationCache`
//  (which persists the same struct as JSON in `UserDefaults`).
//
//  Privacy posture: this type only flows through the `managed`
//  capability path. The Chargers-tab `LocationService` continues to keep
//  fixes device-only and never POSTs them.
//

import Foundation

/// Single best-known location for an opted-in managed device. Drained
/// onto the next sync envelope by `DeviceStateCoordinator.syncOnce()`.
public struct LocationSnapshot: Sendable, Codable, Equatable {

    /// Latitude in decimal degrees, WGS-84.
    public let latitude: Double

    /// Longitude in decimal degrees, WGS-84.
    public let longitude: Double

    /// Horizontal accuracy in metres (CoreLocation's
    /// `CLLocation.horizontalAccuracy`). Lower is better; negative
    /// values from CoreLocation are treated as "invalid" and never make
    /// it into a snapshot.
    public let accuracyMeters: Double

    /// When the fix was captured on the device. Encoded by the same
    /// strategy the rest of the sync envelope uses (the project default
    /// is ISO-8601 with millis).
    public let capturedAt: Date

    public init(
        latitude: Double,
        longitude: Double,
        accuracyMeters: Double,
        capturedAt: Date
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.capturedAt = capturedAt
    }
}
