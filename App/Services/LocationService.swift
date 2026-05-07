//
//  LocationService.swift
//  ExpresScan
//
//  When-in-use location for the Chargers tab — used to compute
//  distance-from-here on each row and promote the nearest charger
//  to a tall "primary" card when within ~150 m.
//
//  Privacy posture: location stays on the device. We never POST it
//  to the server (per privacy-policy.ts: "approximate location, while
//  the app is open, used only to order chargers by distance — not
//  stored on our servers"). The CoreLocation manager is also stopped
//  when the Chargers tab loses focus to keep the location indicator
//  in the status bar honest.
//

import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
public final class LocationService: NSObject, CLLocationManagerDelegate {

    /// Latest known fix. `nil` until permission is granted AND the
    /// system delivers a first reading.
    public private(set) var currentLocation: CLLocation?

    /// Tracks the system authorization status so the UI can
    /// distinguish "asked once, denied" from "haven't asked".
    public private(set) var authorization: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private var isUpdating: Bool = false

    public override init() {
        self.authorization = CLLocationManager().authorizationStatus
        super.init()
        manager.delegate = self
        // Coarse accuracy is plenty for "sort chargers by distance
        // and promote the nearest". The reduced-accuracy mode also
        // keeps us out of the system's "precise location" UI banner
        // when the user is fine with neighborhood-level fixes.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 25 // metres before a callback fires
    }

    // MARK: - Public surface

    /// Trigger the system permission prompt the first time we want
    /// location. Subsequent calls are no-ops once the user has
    /// answered (the OS won't re-prompt regardless).
    public func requestAuthorization() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Begin streaming fixes if authorized. Safe to call multiple
    /// times — idempotent.
    public func startUpdating() {
        guard authorization == .authorizedWhenInUse ||
            authorization == .authorizedAlways else { return }
        guard !isUpdating else { return }
        isUpdating = true
        manager.startUpdatingLocation()
    }

    public func stopUpdating() {
        guard isUpdating else { return }
        isUpdating = false
        manager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    public nonisolated func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorization = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                // User just granted — start streaming via the
                // MainActor-isolated `startUpdating()`, which uses the
                // stored `manager` property and avoids sending the
                // delegate's `manager` parameter across actors.
                self.startUpdating()
            }
        }
    }

    public nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let last = locations.last else { return }
        Task { @MainActor [weak self] in
            self?.currentLocation = last
        }
    }

    public nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // Silent — a transient kCLErrorDomain isn't user-actionable
        // and we never block the UI on a successful fix. The
        // coordinator's distance-sort gracefully degrades to last-
        // seen ordering when `currentLocation` stays nil.
    }
}
