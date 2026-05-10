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

import AuthCore
import Capabilities
import CoreNFC
import DeviceLogging
import DeviceSync
import Foundation
import Logging
import Models
import Networking
import Observation
import UIKit
import UserNotifications

/// `swift-log` channel for the sync round-trip. Failures used to be
/// silent (every `return false` branch in `syncOnce()` had no log),
/// which is why the in-app diagnostics view shows only "APNs
/// registration failed" when sync also fails — APNs has its own
/// logger but the sync path was blank. Phase 3a continuation.
private let syncLog = Logger(label: "sync")

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

    /// SwiftUI-observable reader over the latest envelope's `flags` map.
    /// Refreshed in `applyEnvelope(_:)`.
    public let featureFlagReader: FeatureFlagReader

    /// SwiftUI-observable reader over the on-disk per-device settings.
    /// Refreshed in `applyEnvelope(_:)`. Views may also call
    /// `setLocal(...)` on this reader to write through to the store.
    public let settingsReader: SettingsReader

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

    /// Optional drain for the device-log pipeline (Phase 3a). When `nil`
    /// the sync envelope omits the `logs` field — older servers ignore
    /// it; newer servers see an empty payload. Set by `AppEnvironment`
    /// at bootstrap.
    @ObservationIgnored
    private let logDrain: LogDrain?

    /// Phase 2 / Bundle 2a — managed-device location cache. When `nil`
    /// the sync envelope omits the `location` field. Wired by
    /// `RootCoordinator.ensureDeviceStateCoordinator(...)`.
    @ObservationIgnored
    private let managedLocationCache: ManagedLocationCache?

    /// Feature-flag key gating managed-device location upload. Read
    /// from `featureFlagReader` on every sync — falls back to `false`
    /// so we never POST a fix unless the server has explicitly
    /// enabled the flag for this device.
    @ObservationIgnored
    public static let locationUploadFlagKey = "device.location.upload"

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
        diagnosticsProvider: (@MainActor () async -> SyncRequest.Diagnostics)? = nil,
        logDrain: LogDrain? = nil,
        managedLocationCache: ManagedLocationCache? = nil
    ) {
        self.api = api
        self.settingsStore = settingsStore
        self.cache = cache
        self.service = service ?? DeviceStateService(api: api)
        self.now = now
        self.diagnosticsProvider =
            diagnosticsProvider ?? { @MainActor in
                await Self.defaultDiagnostics()
            }
        self.logDrain = logDrain
        self.managedLocationCache = managedLocationCache
        self.featureFlagReader = FeatureFlagReader()
        self.settingsReader = SettingsReader(store: settingsStore)

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

    /// Refresh the full envelope after a server-side feature-flag change.
    /// Triggered by the `device.feature-flags.changed` SSE event.
    public func handleFeatureFlagsChanged() {
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
        // Phase 3a — logs are owner-scoped PII; drop the buffer so the
        // next user's cold launch starts clean.
        if let drain = logDrain {
            Task { await drain.purge() }
        }
        // Phase 2 / Bundle 2a — clear the cached managed-device
        // location and stop sig-change monitoring. Coords are
        // owner-scoped PII; the next user must not inherit them.
        managedLocationCache?.clear()
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
    ///
    /// Sync is fully independent of APNs registration — a sync that
    /// reaches the server returns `true` even if `pushToken` is null on
    /// the device row. The server may set `needsPushToken=true` in the
    /// envelope as a self-healing hint, but that's not a failure.
    @discardableResult
    public func syncOnce() async -> Bool {
        let pending: [SyncRequest.PendingSetting]
        do {
            pending = try await settingsStore.pendingSettingsForSync()
        } catch {
            // SettingsStore IO failure — skip this tick. The next tick
            // retries.
            syncLog.error(
                "sync skipped: pendingSettings IO failed",
                metadata: [
                    "error.message": "\(error.localizedDescription)",
                    "error.type": "\(type(of: error))",
                    "stage": "pendingSettings",
                ]
            )
            return false
        }
        var diagnostics = await diagnosticsProvider()
        // Track I6 — customer accounts don't report device-health
        // telemetry. Polaris-team (admin-owned) devices keep the
        // full set so the fleet stays observable; customer phones
        // omit battery / thermal state / disk free / low power mode.
        // The owner role is read from the last applied envelope; on
        // first sync (before applyEnvelope ever runs) the role is
        // unknown and we err on the side of NOT sending telemetry.
        if state?.ownerUser.role != .admin {
            diagnostics = diagnostics.scrubbedForCustomerAccount()
        }

        // Phase 3a — drain up to 100 OTel log records into the sync
        // envelope. Drain is non-destructive; we ack only on 200 OK and
        // release on any failure so the next tick retries the same
        // range. Skipped entirely when the drain isn't wired
        // (compat-shim path for tests + early app bootstrap).
        let drained = await logDrain?.pending(maxRecords: 100)
        let logsForRequest: [OTelLogRecord]? =
            (drained?.records).flatMap { $0.isEmpty ? nil : $0 }
        let cursorForRequest: String? = drained?.cursor.map { "\($0)" }

        // Phase 2 / Bundle 2a — attach the cached managed-device
        // location if the capability+flag gate passes. The cache
        // populates itself via sig-change while the app is foregrounded;
        // a `nil` here means either the gate is off, the cache hasn't
        // captured a fix yet, or no cache is wired (test path).
        let locationForRequest: LocationSnapshot? =
            shouldUploadLocation ? managedLocationCache?.current() : nil

        let body = SyncRequest(
            pendingSettings: pending,
            diagnostics: diagnostics,
            logs: logsForRequest,
            logCursor: cursorForRequest,
            location: locationForRequest
        )

        do {
            let envelope = try await service.sync(body)
            await applyEnvelope(envelope)
            if let drained, let cursor = drained.cursor {
                await logDrain?.acknowledge(throughSeq: cursor)
            }
            return true
        } catch APIError.gone {
            // Soft-deleted / revoked device — server returned 410. Hand
            // off to the same revocation path the SSE event uses.
            syncLog.error(
                "sync failed: device gone (410), routing revocation",
                metadata: ["stage": "POST /sync", "status": "410"]
            )
            await logDrain?.release()
            await routeRevocation()
            return false
        } catch APIError.unauthorized {
            syncLog.error(
                "sync failed: unauthorized (401), routing revocation",
                metadata: ["stage": "POST /sync", "status": "401"]
            )
            await logDrain?.release()
            await routeRevocation()
            return false
        } catch {
            // Transient — surface as offline + try again next tick.
            syncLog.error(
                "sync failed: transient error, going offline",
                metadata: [
                    "error.message": "\(error.localizedDescription)",
                    "error.type": "\(type(of: error))",
                    "stage": "POST /sync",
                ]
            )
            await logDrain?.release()
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
        // Refresh the SwiftUI-observable readers so views see the new
        // snapshot on the same tick the envelope lands.
        featureFlagReader.update(envelope.flags)
        settingsReader.update(envelope.settings)
        // Server-driven self-healing: if the server has no APNs token
        // stored but the device thinks notifications are authorized,
        // it sets `needsPushToken`. Re-register to make iOS re-fire the
        // AppDelegate callback, which PUTs the token via PushService.
        if envelope.needsPushToken == true {
            UIApplication.shared.registerForRemoteNotifications()
        }
        // Phase 2 / Bundle 2a — start (or stop) sig-change monitoring
        // based on the latest capability set + feature flag. Idempotent
        // on the cache side, so re-running this on every envelope apply
        // is fine.
        if let cache = managedLocationCache {
            if shouldUploadLocation {
                cache.startSignificantChangeMonitoring()
            } else {
                cache.stop()
            }
        }
    }

    /// Whether the managed-device location upload gate is currently
    /// satisfied: the device must have the `managed` capability AND the
    /// `device.location.upload` feature flag must be `true`. Read on
    /// every sync so toggling either side takes effect on the next
    /// tick without a relaunch.
    private var shouldUploadLocation: Bool {
        guard capabilities.contains(.managed) else { return false }
        return featureFlagReader.bool(Self.locationUploadFlagKey, default: false)
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

    /// Comprehensive diagnostics provider. Reads everything we can off
    /// the device synchronously so the web admin has a full readout for
    /// remote diagnosis (especially for kiosks with no on-device UI).
    /// Tests can inject a stub via the `diagnosticsProvider` parameter
    /// on `init`.
    @MainActor
    private static func defaultDiagnostics() async -> SyncRequest.Diagnostics {
        let device = UIDevice.current

        // Battery monitoring needs to be enabled to read level/state.
        // We re-enable it on every diagnostics tick (idempotent) to
        // avoid stale `unknown`s if something else turned it off.
        let prevBatteryMonitoring = device.isBatteryMonitoringEnabled
        if !prevBatteryMonitoring {
            device.isBatteryMonitoringEnabled = true
        }
        defer {
            // Leave it on once enabled — re-enabling each tick is cheap
            // but flapping it can briefly return `unknown`. Only restore
            // if we're being polite to a test harness that disabled it.
            if !prevBatteryMonitoring && !device.isBatteryMonitoringEnabled {
                device.isBatteryMonitoringEnabled = false
            }
        }

        let batteryLevel: Double? = {
            let level = device.batteryLevel
            // -1 means "unknown" per UIDevice docs.
            return level >= 0 ? Double(level) : nil
        }()

        let batteryState: SyncRequest.Diagnostics.BatteryState = {
            switch device.batteryState {
            case .unknown: return .unknown
            case .unplugged: return .unplugged
            case .charging: return .charging
            case .full: return .full
            @unknown default: return .unknown
            }
        }()

        let thermalState: SyncRequest.Diagnostics.ThermalState = {
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: return .nominal
            case .fair: return .fair
            case .serious: return .serious
            case .critical: return .critical
            @unknown default: return .nominal
            }
        }()

        let diskFreeBytes: Int64? = {
            do {
                let url = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: false
                )
                let values = try url.resourceValues(
                    forKeys: [.volumeAvailableCapacityForImportantUsageKey]
                )
                if let bytes = values.volumeAvailableCapacityForImportantUsage {
                    return bytes
                }
            } catch {
                // Best-effort — leave nil.
            }
            return nil
        }()

        // Read UN authorization status. `await` is fine — the call is
        // cheap and runs once per sync (60s).
        let pushPermission: SyncRequest.Diagnostics.PushPermission = await {
            let settings = await UNUserNotificationCenter.current()
                .notificationSettings()
            switch settings.authorizationStatus {
            case .authorized: return .authorized
            case .denied: return .denied
            case .notDetermined: return .notDetermined
            case .provisional: return .provisional
            case .ephemeral: return .ephemeral
            @unknown default: return .notDetermined
            }
        }()

        let backgroundRefreshStatus: SyncRequest.Diagnostics.BackgroundRefreshState = {
            switch UIApplication.shared.backgroundRefreshStatus {
            case .available: return .available
            case .denied: return .denied
            case .restricted: return .restricted
            @unknown default: return .denied
            }
        }()

        let nfcAvailable = NFCNDEFReaderSession.readingAvailable

        return SyncRequest.Diagnostics(
            appVersion: BuildConfig.appVersion,
            osVersion: device.systemVersion,
            model: device.model,
            pushPermission: pushPermission,
            nfcAvailable: nfcAvailable,
            pendingUploads: 0,
            reconnectCount: 0,
            platform: device.systemName,
            localizedModel: device.localizedModel,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier,
            apnsEnvironment: BuildConfig.apnsEnvironment,
            // pushTokenLast8 / network info are best wired by a richer
            // diagnostics provider that has access to authStore +
            // NWPathMonitor; the default fallback fills in everything
            // we can read off the OS without dependencies.
            pushTokenLast8: nil,
            // CoreNFC has no separate "permission denied" state — the
            // user grants per-session at the system sheet. So
            // `nfcPermission` mirrors `nfcAvailable` for now.
            nfcPermission: nfcAvailable ? .authorized : .unavailable,
            backgroundRefreshStatus: backgroundRefreshStatus,
            localNetworkPermission: nil,
            batteryLevel: batteryLevel,
            batteryState: batteryState,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: thermalState,
            networkInterface: nil,
            networkIsConstrained: nil,
            networkIsExpensive: nil,
            diskFreeBytes: diskFreeBytes
        )
    }
}
