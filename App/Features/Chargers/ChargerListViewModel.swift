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

import Foundation
import Observation

import Networking

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
        case offline = "Offline"

        public var id: String { rawValue }
    }

    public private(set) var entries: [ChargerListEntry] = []
    public private(set) var loadState: LoadState = .idle
    public var filter: OnlineStatusFilter = .all

    /// Filtered entries, derived from `entries + filter`. The view
    /// reads this; it changes whenever either input changes.
    public var displayEntries: [ChargerListEntry] {
        switch filter {
        case .all:     return entries
        case .online:  return entries.filter { $0.state.isOnline }
        case .offline: return entries.filter { !$0.state.isOnline }
        }
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
