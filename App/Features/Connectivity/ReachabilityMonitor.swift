//
//  ReachabilityMonitor.swift
//  ExpresScan
//
//  Distinguishes two kinds of connectivity loss:
//
//   1. `.deviceOffline` — phone has no Wi-Fi or cellular path
//      (`NWPathMonitor` reports `.unsatisfied`).
//   2. `.serverUnreachable` — phone has internet, but our backend
//      isn't responding (probe failures or sustained transport
//      errors reported by `APIClient`).
//
//  Mounted at `RootView` to drive `OfflineOverlay`, but the monitor
//  itself is platform-agnostic so it can be used by any caller that
//  needs a fused signal.
//

import Foundation
import Network
import Observation
import os

private let reachLog = Logger(subsystem: "com.example.expresscharge.ios", category: "reachability")

/// Source of truth for whether the app can talk to the backend. Pulls
/// from two probes — device path and server health — and exposes a
/// single tri-state.
@MainActor
@Observable
public final class ReachabilityMonitor {

    public enum State: Equatable, Sendable {
        case online
        case deviceOffline
        case serverUnreachable
    }

    public private(set) var state: State = .online
    /// Wall-clock time of the next scheduled probe. The overlay
    /// reads this to render a countdown ring while we're waiting
    /// for backoff to elapse.
    public private(set) var nextProbeAt: Date?
    /// Backoff window in seconds for the *current* sleep interval
    /// — used by the overlay to compute progress (`remaining /
    /// currentBackoffSeconds`). Always > 0 when `nextProbeAt` is
    /// set; `nil` when no backoff is pending.
    public private(set) var currentBackoffSeconds: Int?

    private let healthURL: URL
    private let session: URLSession
    private let monitor: NWPathMonitor
    private var hasNetworkPath: Bool = true
    private var probeTask: Task<Void, Never>?
    private var streakOfFailures: Int = 0
    /// Backoff progression (seconds) used between server probes when
    /// the server is unhealthy.
    private static let backoffSeconds: [UInt64] = [1, 2, 5, 10, 20, 30]
    /// Cadence (seconds) of background server probes while we believe
    /// the server is online. Long enough to be cheap, short enough to
    /// catch outages within ~half a minute.
    private static let healthyPollInterval: UInt64 = 20

    /// `apiBaseURL` is appended with `/api/health` (which the backend
    /// already serves for liveness checks). `urlSession` defaults to
    /// `.shared`; tests can inject an in-memory `URLSession`.
    ///
    /// `nonisolated` so the process-wide singleton (`AppEnvironment`)
    /// can construct the monitor before the SwiftUI hierarchy comes
    /// online, without needing to hop to `MainActor`.
    public nonisolated init(
        apiBaseURL: URL,
        urlSession: URLSession = .shared
    ) {
        self.healthURL = apiBaseURL.appendingPathComponent("api/health")
        self.session = urlSession
        self.monitor = NWPathMonitor()
    }

    /// Begin observing path changes and probing the backend. Idempotent.
    public func start() {
        guard probeTask == nil else { return }

        let queue = DispatchQueue(label: "reachability.path")
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                await self?.handlePathUpdate(satisfied: satisfied)
            }
        }
        monitor.start(queue: queue)

        probeTask = Task { [weak self] in
            await self?.probeLoop()
        }
    }

    /// Tear down monitoring. Useful in tests; the production app uses
    /// the monitor for the entire process lifetime.
    public func stop() {
        monitor.cancel()
        probeTask?.cancel()
        probeTask = nil
    }

    /// `APIClient` calls this when a request fails with a transport
    /// error or sustained 5xx so the overlay reacts immediately
    /// instead of waiting for the next periodic probe.
    public nonisolated func reportTransportFailure() {
        Task { @MainActor [weak self] in
            await self?.probeOnce(reason: "transport-failure")
        }
    }

    /// User-triggered reconnect (`OfflineOverlay`'s "Try again").
    public nonisolated func retryNow() {
        Task { @MainActor [weak self] in
            await self?.probeOnce(reason: "user-retry")
        }
    }

    // MARK: - Internals

    private func handlePathUpdate(satisfied: Bool) async {
        hasNetworkPath = satisfied
        if !satisfied {
            transition(to: .deviceOffline, reason: "no-path")
            return
        }
        // Path came back — probe to confirm the server is also up.
        await probeOnce(reason: "path-restored")
    }

    private func probeLoop() async {
        // Initial probe at boot.
        await probeOnce(reason: "boot")
        while !Task.isCancelled {
            let nap: UInt64
            switch state {
            case .online:
                nap = Self.healthyPollInterval
            case .deviceOffline:
                // Path callback drives recovery; sleep long.
                nap = 60
            case .serverUnreachable:
                let idx = min(streakOfFailures, Self.backoffSeconds.count - 1)
                nap = Self.backoffSeconds[idx]
            }
            // Publish countdown info so the overlay can show "next
            // attempt in Xs" with a ring. Only meaningful while
            // we're not online.
            if state != .online {
                currentBackoffSeconds = Int(nap)
                nextProbeAt = Date().addingTimeInterval(TimeInterval(nap))
            } else {
                currentBackoffSeconds = nil
                nextProbeAt = nil
            }
            try? await Task.sleep(nanoseconds: nap * 1_000_000_000)
            await probeOnce(reason: "scheduled")
        }
    }

    private func probeOnce(reason: String) async {
        guard hasNetworkPath else {
            transition(to: .deviceOffline, reason: "probe-no-path/\(reason)")
            return
        }
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 6
        do {
            let (_, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<500).contains(code) {
                // 4xx still means the server is alive enough to
                // answer; only transport errors / 5xx count as "down".
                streakOfFailures = 0
                transition(to: .online, reason: "probe-ok/\(code)/\(reason)")
            } else {
                streakOfFailures += 1
                transition(to: .serverUnreachable, reason: "probe-5xx/\(code)/\(reason)")
            }
        } catch {
            streakOfFailures += 1
            transition(to: .serverUnreachable, reason: "probe-throw/\(reason)")
        }
    }

    private func transition(to next: State, reason: String) {
        if state == next { return }
        reachLog.info("reachability \(self.state.label, privacy: .public) → \(next.label, privacy: .public) [\(reason, privacy: .public)]")
        state = next
    }
}

private extension ReachabilityMonitor.State {
    var label: String {
        switch self {
        case .online:            return "online"
        case .deviceOffline:     return "device-offline"
        case .serverUnreachable: return "server-unreachable"
        }
    }
}
