//
//  ChargerListViewModel.swift
//  ExpresScan
//
//  Wave 6 / Slice I — owns the chargers list backing the iOS Chargers
//  tab. Calls `GET /api/devices` (slice I backend) on init / pull-to-
//  refresh. Tracks an Online-status filter (`.all` / `.online` /
//  `.offline`) — the only UI knob in v1 (Type filter was retired with
//  the iOS-Chargers-only scope; non-charger device management is
//  web-only).
//

import CoreLocation
import Foundation
import Networking
import Observation

@MainActor
@Observable
public final class ChargerListViewModel {

    public enum LoadState: Equatable, Sendable {
        case idle
        case loading
        case ok
        case error(String)
    }

    public enum OnlineStatusFilter: String, Sendable, CaseIterable, Identifiable {
        case all = "All"
        case online = "Online"

        public var id: String { rawValue }
    }

    public private(set) var entries: [ChargerListEntry] = []
    public private(set) var loadState: LoadState = .idle
    public var filter: OnlineStatusFilter = .all

    /// User's current location, set by the parent view from
    /// `LocationService.currentLocation`. `nil` when location
    /// permission is denied or no fix is available — the list then
    /// falls back to last-seen ordering.
    public var currentLocation: CLLocation?

    /// Threshold under which a charger is considered "right here" and
    /// gets promoted to the tall primary card. ~150 m is comfortable
    /// for the coarse-accuracy fixes we request (`kCLLocationAccuracy
    /// HundredMeters`); short enough that two adjacent installations
    /// at a public charging plaza don't both qualify.
    public static let proximityThresholdMeters: Double = 150

    /// Filtered + sorted entries. Sort order:
    ///   1. By distance ascending when location is available; chargers
    ///      without coordinates fall to the bottom.
    ///   2. Otherwise by lastSeen descending (server's default).
    public var displayEntries: [ChargerListEntry] {
        let filtered: [ChargerListEntry]
        switch filter {
        case .all:
            filtered = entries
        case .online:
            // Unmanaged chargers (no state) are always considered
            // online — they're physically present, just not reporting.
            filtered = entries.filter { ($0.state ?? .idle).isOnline }
        }

        guard let here = currentLocation else { return filtered }

        return filtered.sorted { a, b in
            let da = distance(from: here, to: a)
            let db = distance(from: here, to: b)
            switch (da, db) {
            case let (.some(la), .some(lb)): return la < lb
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none):
                let la = a.lastSeenAt ?? .distantPast
                let lb = b.lastSeenAt ?? .distantPast
                return la > lb
            }
        }
    }

    /// The single charger close enough to be promoted to the tall
    /// "primary" card. Always the first of `displayEntries` when its
    /// distance is under the threshold; `nil` otherwise.
    public var primaryEntry: ChargerListEntry? {
        guard let first = displayEntries.first,
              let here = currentLocation,
              let d = distance(from: here, to: first),
              d <= Self.proximityThresholdMeters
        else { return nil }
        return first
    }

    /// Everything else when a primary card is showing; the full list
    /// otherwise.
    public var secondaryEntries: [ChargerListEntry] {
        guard primaryEntry != nil else { return displayEntries }
        return Array(displayEntries.dropFirst())
    }

    /// Distance in metres from `here` to the charger's coordinates,
    /// or `nil` when the entry doesn't carry lat/lon.
    public func distance(
        from here: CLLocation,
        to entry: ChargerListEntry
    ) -> Double? {
        guard let lat = entry.latitude, let lon = entry.longitude else {
            return nil
        }
        let target = CLLocation(latitude: lat, longitude: lon)
        return here.distance(from: target)
    }

    /// Whether the list has zero entries to show under the current
    /// filter. Drives the empty-state vs list rendering.
    public var isEmpty: Bool { displayEntries.isEmpty }

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    /// Initial load + manual refresh. Exposes `loadState` for the
    /// view's skeleton/error rendering; idempotent if called while
    /// already loading.
    public func refresh() async {
        if case .loading = loadState { return }
        loadState = .loading

        let endpoint = Endpoint(path: "/api/devices", method: .get)
        do {
            let response: ChargersListResponse = try await api.request(endpoint)
            entries = response.chargers
            loadState = .ok
        } catch let error as APIError {
            loadState = .error(message(for: error))
        } catch {
            loadState = .error("Couldn't load chargers. Try again.")
        }
    }

    private func message(for error: APIError) -> String {
        switch error {
        case .unauthorized:
            return "Sign in again to see chargers."
        case .forbidden:
            return "You don't have access to manage chargers."
        case .gone:
            return "This iPhone was deregistered. Sign in again."
        case .network:
            return "Connect to Wi-Fi or cellular and pull to refresh."
        default:
            return "Couldn't load chargers. Try again."
        }
    }
}
