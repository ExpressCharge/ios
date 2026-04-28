//
//  DeviceStateCoordinator.swift
//  ExpresScan
//
//  Wave 6 / Slice G. Owns the live `DeviceState` envelope and drives the
//  consolidated 60-second sync loop that replaced the old empty-bodied
//  `/api/devices/heartbeat`. Surfaces capabilities, settings, and the
//  connection-status surface that `ReadyView` + `SettingsView` +
//  `DiagnosticsSheet` all read from.
//
//  Wire-up:
//   - `RootCoordinator` constructs one of these alongside the
//     `ScanCoordinator` once credentials are in place.
//   - `ScanCoordinator` forwards two SSE event types to us:
//     `device.capabilities.changed` and `device.settings.changed`. The
//     existing `EventStreamReconnector` event router lives in
//     `ScanCoordinator.handleSSEEvent`; we reuse that single tap.
//   - The cache + settings store are owned by us, persisted on every
//     successful sync; cache is read on `bootstrap()` so the SwiftUI
//     shell can render with cached capabilities BEFORE the first
//     network call resolves (P1-9).
//
//  Concurrency: `@MainActor`-isolated so SwiftUI views read `state`
//  directly. The sync loop is a single child `Task`; its body marshals
//  via `await` to the actors it touches (`SettingsStore` actor +
//  `APIClient` actor).
//

import Foundation
import Observation
import UIKit

import AuthCore
import Capabilities
import DeviceSync
import Models
import Networking

@MainActor
@Observable
public final class DeviceStateCoordinator {

    // MARK: - Public observable state

    /// Live envelope. `nil` until either the cache or the first network
    /// call resolves (whichever comes first); both `bootstrap()` paths
    /// populate this before returning.
    public private(set) var state: DeviceState?

    /// Capabilities the SwiftUI shell reads. Sourced from `state` once
    /// it's resolved, falling back to the cache during the cold-launch
    /// window. Never `nil` — falls back to the registration default
    /// (`{.scanner, .user}`) if both the cache and the network are
    /// empty.
    public var capabilities: Set<DeviceCapability> {
        if let s = state {
            return Set(s.capabilities)
        }
        if let cached = cachedCapabilities {
            return cached
        }
        return Self.defaultCapabilities
    }

    /// Mirrors the existing `ScanCoordinator.ConnectionStatus` enum so
    /// `ReadyView` + `SettingsView` + `DiagnosticsSheet` can swap their
    /// data source without changing their pill rendering.
    public private(set) var connectionStatus: ConnectionStatus = .offline

    /// Last successful sync time. Surfaced in `DiagnosticsSheet` as
    /// "Last heartbeat" — same surface, different data source.
    public private(set) var lastHeartbeatAt: Date?

    /// Reconnect counter, mirrored from the SSE link by `ScanCoordinator`.
    /// We don't drive this ourselves — but exposing it here means
    /// `DiagnosticsSheet` can read everything off one coordinator.
    public private(set) var reconnectCount: Int = 0

    /// Default capability set used when both the cache and the network
    /// are empty. Matches Slice H's registration default.
    public static let defaultCapabilities: Set<DeviceCapability> = [.scanner, .user]

    /// Sync cadence. Public for tests.
    public static let syncInterval: TimeInterval = 60

    // MARK: - Dependencies

    @ObservationIgnored
    private let api: APIClient
    @ObservationIgnored
    private let settingsStore: SettingsStore
    @ObservationIgnored
    private let cache: CapabilityCache
    @ObservationIgnored
    private let service: DeviceStateService
    @ObservationIgnored
    private let now: @Sendable () -> Date
    @ObservationIgnored
    private let diagnosticsProvider: @MainActor () async -> SyncRequest.Diagnostics

    @ObservationIgnored
    private weak var router: RootCoordinator?

    // MARK: - Internal state

    /// Cached capability set read at bootstrap. Lives only until the
    /// first sync resolves and `state` is set.
    @ObservationIgnored
    private var cachedCapabilities: Set<DeviceCapability>?

    /// 60-second loop task. Cancelled in `stop()` and `deinit`.
    @ObservationIgnored
    private var loopTask: Task<Void, Never>?

    /// Whether the loop is currently allowed to run. Set `false` on
    /// background to suspend the cadence; `true` on foreground.
    @ObservationIgnored
    private var foregrounded: Bool = true

    /// `true` between `bootstrap()` and the first successful sync.
    @ObservationIgnored
    private var bootstrapped: Bool = false

    // MARK: - Init

    public init(
        api: APIClient,
        settingsStore: SettingsStore,
        cache: CapabilityCache = CapabilityCache(),
        service: DeviceStateService? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        diagnosticsProvider: (@MainActor () async -> SyncRequest.Diagnostics)? = nil
    ) {
        self.api = api
        self.settingsStore = settingsStore
        self.cache = cache
        self.service = service ?? DeviceStateService(api: api)
        self.now = now
        self.diagnosticsProvider = diagnosticsProvider ?? { @MainActor in
            await Self.defaultDiagnostics()
        }

        // Best-effort cache read so the first capability surface is the
        // last-known set, not the hard default.
        self.cachedCapabilities = cache.read()
    }

    deinit {
        loopTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Bind to the parent router so revocation paths can route back to
    /// `.welcome` via the same path `ScanCoordinator` already uses.
    public func attach(router: RootCoordinator) {
        self.router = router
    }

    /// One-shot startup: read the cache (already done in `init`), call
    /// `GET /me/state` once, then start the periodic sync loop. Safe to
    /// call multiple times — subsequent calls are no-ops.
    public func bootstrap() {
        guard loopTask == nil else { return }
        bootstrapped = true
        connectionStatus = .connecting

        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    /// Cancel the sync loop. Called on sign-out.
    public func stop() {
        loopTask?.cancel()
        loopTask = nil
        connectionStatus = .offline
        bootstrapped = false
    }

    // MARK: - Foreground/background hooks

    /// Called from `RootView`'s `scenePhase` observer when the scene
    /// becomes active. Triggers an immediate sync regardless of where
    /// we are in the 60s cadence.
    public func handleEnterForeground() {
        foregrounded = true
        // Kick an immediate sync. The loop's own sleep continues in
        // parallel; the next loop tick will absorb the duplicate.
        Task { [weak self] in
            await self?.syncOnce()
        }
    }

    /// Called from `RootView` on background. Suspends the cadence —
    /// `runLoop` checks `foregrounded` before each sleep step.
    public func handleEnterBackground() {
        foregrounded = false
    }

    // MARK: - SSE event routing
    //
    // `ScanCoordinator.handleSSEEvent` calls these for the two new event
    // types. We don't subscribe to the SSE stream directly — there's
    // exactly one consumer of `EventStreamReconnector.events()` and
    // forking it would force two parallel SSE connections.

    /// Refresh the full envelope after a server-side capability change.
    /// Triggered by the `device.capabilities.changed` SSE event.
    public func handleCapabilitiesChanged() {
        Task { [weak self] in
            await self?.refreshState()
        }
    }

    /// Apply server-merged settings and refresh the envelope. Triggered
    /// by the `device.settings.changed` SSE event.
    public func handleSettingsChanged() {
        Task { [weak self] in
            await self?.refreshState()
        }
    }

    /// Token revocation hand-off. The `ScanCoordinator` already has the
    /// `handleTokenRevoked` flow that wipes the keychain + routes
    /// `.welcome`; we just clear our local state and the cache so the
    /// next user's cold launch doesn't render with the previous user's
    /// capabilities.
    public func handleTokenRevoked() {
        cache.clear()
        state = nil
        cachedCapabilities = nil
        stop()
    }

    /// Mirror the `ScanCoordinator.noteReconnectAttempt()` surface so
    /// diagnostics pulls a single source of truth.
    public func noteReconnectAttempt() {
        reconnectCount += 1
        connectionStatus = .reconnecting
    }

    /// Called from `ScanCoordinator` on the SSE `connected` event so
    /// our connectionStatus surface reaches `.online` even if a sync
    /// hasn't yet completed.
    public func noteSSEConnected() {
        if connectionStatus != .online {
            connectionStatus = .online
        }
    }

    // MARK: - Loop body

    private func runLoop() async {
        // 1) Initial GET /me/state. Bypasses the sync POST body — we
        //    don't have anything to flush on cold launch.
        await refreshState()

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(Self.syncInterval))
            } catch {
                return
            }
            if Task.isCancelled { return }
            // Suspend cadence in background. We resume on foreground via
            // the immediate sync kick + the next sleep tick.
            if !foregrounded { continue }
            await syncOnce()
        }
    }

    /// Single iteration: pull pending settings + diagnostics, POST the
    /// sync, apply the merged response.
    @discardableResult
    public func syncOnce() async -> Bool {
        let pending: [SyncRequest.PendingSetting]
        do {
            pending = try await settingsStore.pendingSettingsForSync()
        } catch {
            // SettingsStore IO failure — skip this tick. The next tick
            // retries.
            return false
        }
        let diagnostics = await diagnosticsProvider()
        let body = SyncRequest(pendingSettings: pending, diagnostics: diagnostics)

        do {
            let envelope = try await service.sync(body)
            await applyEnvelope(envelope)
            return true
        } catch APIError.gone {
            // Soft-deleted / revoked device — server returned 410. Hand
            // off to the same revocation path the SSE event uses.
            await routeRevocation()
            return false
        } catch APIError.unauthorized {
            await routeRevocation()
            return false
        } catch {
            // Transient — surface as offline + try again next tick.
            connectionStatus = .offline
            return false
        }
    }

    /// `GET /me/state` without the sync POST. Used on bootstrap and on
    /// SSE-driven refresh.
    private func refreshState() async {
        do {
            let envelope = try await service.fetchState()
            await applyEnvelope(envelope)
        } catch APIError.gone, APIError.unauthorized {
            await routeRevocation()
        } catch {
            connectionStatus = .offline
        }
    }

    private func applyEnvelope(_ envelope: DeviceState) async {
        state = envelope
        connectionStatus = .online
        lastHeartbeatAt = now()
        cachedCapabilities = nil
        // Cache the capabilities on every successful sync.
        cache.write(Set(envelope.capabilities))
        // Apply the merged settings to the on-disk store. Best-effort —
        // a failure here doesn't fail the sync (the next tick retries
        // via the LWW path).
        try? await settingsStore.applyMerged(envelope.settings)
    }

    private func routeRevocation() async {
        handleTokenRevoked()
        // Hand off to the existing token-revoked flow on
        // `ScanCoordinator` so the keychain wipe + .welcome route
        // sequence runs once, in one place.
        if let scan = router?.scan {
            await scan.handleTokenRevoked()
        }
    }

    // MARK: - Default diagnostics

    /// Fallback diagnostics provider. Reads the OS version + model from
    /// `UIDevice` + the bundle. The provider is overridable so unit
    /// tests don't depend on `UIDevice` at all.
    @MainActor
    private static func defaultDiagnostics() async -> SyncRequest.Diagnostics {
        let device = UIDevice.current
        let appVersion = BuildConfig.appVersion
        let osVersion = device.systemVersion
        let model = device.model
        return SyncRequest.Diagnostics(
            appVersion: appVersion,
            osVersion: osVersion,
            model: model,
            pushPermission: .notDetermined,
            nfcAvailable: true,
            pendingUploads: 0,
            reconnectCount: 0
        )
    }
}
