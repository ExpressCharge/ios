//
//  ManagedLocationCache.swift
//  ExpresScan
//
//  Phase 2 / Bundle 2a — parallel to `App/Services/LocationService.swift`.
//
//  `LocationService` is the Chargers-tab fix used to sort rows by
//  distance. Its privacy contract is "device-only, never POSTs". To
//  keep that contract intact, the managed-device location reporting
//  for admin-locate flows lives in this **separate** service. Both can
//  reuse the existing When-In-Use authorisation grant — sig-change does
//  NOT need `Always` and we deliberately do NOT add a
//  `UIBackgroundModes/location` entry.
//
//  Surface (per Phase 2 plan):
//   - `current()`                              — read cached snapshot
//   - `startSignificantChangeMonitoring()`     — sig-change while WhenInUse
//   - `stop()`                                 — stop sig-change + reset
//   - `requestOneShot(reason:) async`          — single-fix for silent push
//   - persists the latest snapshot in `UserDefaults` under
//     `managed.location.snapshot.v1` so reboots don't lose last-known.
//
//  Gates: callers (`DeviceStateCoordinator.syncOnce()` and the silent-
//  push handler) check `DeviceCapability.managed` membership AND the
//  `device.location.upload` feature flag before consulting this cache.
//  We don't gate inside the cache itself so unit tests can drive the
//  service without standing up the full envelope plumbing.
//

import CoreLocation
import DeviceSync
import Foundation
import Logging
import Observation

/// Reasons a one-shot fix may be requested. Used for log breadcrumbs;
/// no functional difference between cases today.
public enum ManagedLocationOneShotReason: String, Sendable {
    case silentPushLocate
    case manualRefresh
}

@MainActor
@Observable
public final class ManagedLocationCache: NSObject, CLLocationManagerDelegate {

    // MARK: - Public observable state

    /// Latest cached snapshot. Loaded from `UserDefaults` on init so a
    /// cold launch sees the last-known fix even before sig-change fires.
    public private(set) var snapshot: LocationSnapshot?

    // MARK: - Configuration

    /// `UserDefaults` key for the persisted snapshot. Versioned so a
    /// future schema change can rev cleanly.
    public static let defaultsKey = "managed.location.snapshot.v1"

    // MARK: - Dependencies

    @ObservationIgnored
    private let manager: CLLocationManager
    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let now: @Sendable () -> Date
    @ObservationIgnored
    private let log = Logger(label: "managed-location")

    // MARK: - Internal state

    @ObservationIgnored
    private var sigChangeActive: Bool = false

    /// Continuations awaiting a one-shot fix. We support multiple
    /// concurrent requests resolved by a single delegate callback.
    @ObservationIgnored
    private var pendingOneShots: [CheckedContinuation<LocationSnapshot?, Never>] = []

    // MARK: - Init

    public init(
        manager: CLLocationManager = CLLocationManager(),
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.manager = manager
        self.defaults = defaults
        self.now = now
        super.init()
        manager.delegate = self
        // Sig-change inherently coarse; we don't need to set
        // `desiredAccuracy` here. One-shot `requestLocation()` is OS-
        // driven and respects whatever accuracy the user has granted.
        self.snapshot = Self.readPersisted(defaults: defaults)
    }

    // MARK: - Public surface

    /// The cached snapshot, drained by sync.
    public func current() -> LocationSnapshot? {
        snapshot
    }

    /// Start monitoring significant location changes. Idempotent. Does
    /// not trigger a permission prompt — relies on the existing
    /// When-In-Use authorisation that `LocationService` requests for
    /// the Chargers tab.
    public func startSignificantChangeMonitoring() {
        guard !sigChangeActive else { return }
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            log.debug(
                "ManagedLocationCache: sig-change skipped",
                metadata: ["authorization": "\(String(describing: status))"]
            )
            return
        }
        sigChangeActive = true
        manager.startMonitoringSignificantLocationChanges()
    }

    /// Stop sig-change monitoring. Idempotent.
    public func stop() {
        if sigChangeActive {
            manager.stopMonitoringSignificantLocationChanges()
            sigChangeActive = false
        }
        // Resolve any pending one-shots so callers don't leak.
        let waiters = pendingOneShots
        pendingOneShots.removeAll()
        for c in waiters { c.resume(returning: nil) }
    }

    /// Clear the cached snapshot (in-memory + on-disk) and stop
    /// sig-change monitoring. Called on token revocation so the next
    /// user's cold launch starts clean.
    public func clear() {
        stop()
        snapshot = nil
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    /// Request a single fresh fix. Reuses any existing authorisation;
    /// does not prompt. Returns `nil` if authorisation is missing or
    /// CoreLocation fails. Multiple concurrent calls are coalesced —
    /// the next delegate callback resolves all of them with the same
    /// snapshot.
    public func requestOneShot(
        reason: ManagedLocationOneShotReason
    ) async -> LocationSnapshot? {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            log.debug(
                "ManagedLocationCache: one-shot skipped",
                metadata: [
                    "authorization": "\(String(describing: status))",
                    "reason": "\(reason.rawValue)",
                ]
            )
            return nil
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<LocationSnapshot?, Never>) in
            pendingOneShots.append(continuation)
            // `requestLocation()` produces exactly one
            // `didUpdateLocations` (or `didFailWithError`) callback.
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    public nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let last = locations.last else { return }
        // Reject obviously-bogus fixes. CoreLocation returns negative
        // accuracy when the fix is invalid.
        guard last.horizontalAccuracy >= 0 else { return }
        // Capture sendable scalars before hopping back to the actor.
        let lat = last.coordinate.latitude
        let lon = last.coordinate.longitude
        let acc = last.horizontalAccuracy
        let timestamp = last.timestamp
        Task { @MainActor [weak self] in
            guard let self else { return }
            let snap = LocationSnapshot(
                latitude: lat,
                longitude: lon,
                accuracyMeters: acc,
                capturedAt: timestamp
            )
            self.snapshot = snap
            Self.persist(snap, defaults: self.defaults)
            // Resolve any one-shot waiters with this fix.
            let waiters = self.pendingOneShots
            self.pendingOneShots.removeAll()
            for c in waiters { c.resume(returning: snap) }
        }
    }

    public nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Resolve waiters with `nil` so callers don't hang. The
            // cached snapshot stays whatever it was.
            let waiters = self.pendingOneShots
            self.pendingOneShots.removeAll()
            for c in waiters { c.resume(returning: nil) }
        }
    }

    // MARK: - Persistence

    private static func readPersisted(defaults: UserDefaults) -> LocationSnapshot? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LocationSnapshot.self, from: data)
    }

    private static func persist(_ snapshot: LocationSnapshot, defaults: UserDefaults) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) {
            defaults.set(data, forKey: defaultsKey)
        }
    }
}
