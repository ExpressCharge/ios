//
//  ScanCoordinator.swift
//  ExpresScan
//
//  Single owner of the Scan feature's state machine. Wires together:
//
//   - `EventStreamReconnector` for the SSE link to the backend.
//   - `PushService` for APNs-delivered scan requests (out-of-process arrival
//     path).
//   - `NFCService` for the actual `NFCTagReaderSession` invocation.
//   - `DeviceStateCoordinator` for the consolidated 60-second device-
//     state sync (replaced the empty-bodied `/heartbeat` endpoint).
//   - `ScanResultQueue` for offline scan-result retries.
//
//  The coordinator is `@MainActor`-isolated so SwiftUI can read its
//  `state` directly without crossing actor boundaries. Background work
//  (SSE byte parsing, APNs delegate callbacks, NFC delegate callbacks)
//  marshals back here via `Task { @MainActor in … }`.
//
//  Spec:
//    - `50-ios.md` § "State machine"
//    - `50-ios.md` § "Scan flow"
//    - `50-ios.md` § "Push handling"
//    - `60-security.md` § 6 (HMAC nonce)
//

import Foundation
import Observation

import AuthCore
import Crypto
import Models
import Networking

/// Source attribution for an incoming `ScanRequest` — used for
/// debouncing (push + SSE both deliver the same request) and for
/// diagnostics.
public enum ScanRequestSource: String, Sendable, Equatable {
    case push
    case sse
}

/// Connection-status flavour of `ScanState` for the home screen pill.
/// Distinct from `ScanState` — multiple `ScanState` cases share the same
/// pill ("Online" covers both `.readyToScan` and `.scanRequested`).
public enum ConnectionStatus: Equatable, Sendable {
    case offline
    case connecting
    case online
    /// SSE dropped, reconnect attempt scheduled.
    case reconnecting
}

@MainActor
@Observable
public final class ScanCoordinator {

    // MARK: - Public, observable state

    /// Single source of truth for the Scan feature.
    public private(set) var state: ScanState = .idle

    /// Live SSE/push connection status. Independent of `state` so the
    /// pill can show "Reconnecting" while we still display a stale
    /// `.scanRequested` card.
    public private(set) var connectionStatus: ConnectionStatus = .offline

    /// Time the active `.scanRequested` was armed locally — used by the
    /// `ScanActiveView` countdown ring driver.
    public private(set) var armedAt: Date?

    /// Last heartbeat success time, surfaced in the diagnostics sheet.
    public private(set) var lastHeartbeatAt: Date?

    /// Number of reconnect attempts the underlying reconnector has made
    /// in the lifetime of this coordinator (resets on `startConnecting`).
    public private(set) var reconnectCount: Int = 0

    /// Number of pending scan-result POST bodies queued for retry. The
    /// home screen surfaces this as a "(N pending)" badge.
    public private(set) var pendingScanResultCount: Int = 0

    /// Optional toast surfaced from `handleTokenRevoked()` etc. Cleared
    /// after the UI displays it.
    public private(set) var transientToast: String?

    // MARK: - Dependencies (constructor-injected)

    @ObservationIgnored
    private let environment: AppEnvironment
    @ObservationIgnored
    private let nfc: NFCService
    /// Optional reference to the device-state coordinator so SSE event
    /// routing forwards `device.capabilities.changed` /
    /// `device.settings.changed` to the right place. `nil` in unit
    /// tests that don't exercise the consolidated sync.
    @ObservationIgnored
    private weak var deviceState: DeviceStateCoordinator?
    @ObservationIgnored
    private let queue: ScanResultQueue
    /// Closure injected so unit tests can swap in a stub. In production
    /// this is `EventStreamReconnector(env:)`.
    @ObservationIgnored
    private let makeReconnector: @MainActor () -> EventStreamReconnector
    /// Closure for `URLSession`-based clock — overridable in tests.
    @ObservationIgnored
    private let now: @Sendable () -> Date

    @ObservationIgnored
    private var streamTask: Task<Void, Never>?
    @ObservationIgnored
    private var queueDrainTask: Task<Void, Never>?
    @ObservationIgnored
    private var reconnector: EventStreamReconnector?
    /// Recent in-memory dedup record for `(pairingCode, expiresAt)` —
    /// covers the 90 s TTL window. Mirrored to UserDefaults so a
    /// background-tap-relaunch doesn't re-arm the same pairing.
    @ObservationIgnored
    private var recentPairings: [String: Date] = [:]
    @ObservationIgnored
    private var coordinatorRouter: RootCoordinator?

    /// Coalesce window: 90 s, matching the backend pairing TTL.
    static let pairingCoalesceWindow: TimeInterval = 90

    private static let pairingCacheKey = "ExpresScan.RecentPairingsV1"

    public init(
        environment: AppEnvironment,
        nfc: NFCService = .init(),
        deviceState: DeviceStateCoordinator? = nil,
        queue: ScanResultQueue? = nil,
        reconnectorFactory: (@MainActor () -> EventStreamReconnector)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.environment = environment
        self.nfc = nfc
        self.deviceState = deviceState
        self.queue = queue ?? ScanResultQueue(api: environment.api)
        self.makeReconnector = reconnectorFactory ?? { @MainActor [environment] in
            EventStreamReconnector(environment: environment)
        }
        self.now = now
        loadRecentPairings()
    }

    /// Bind the parent router so `handleTokenRevoked()` can navigate
    /// back to `.welcome`. Set once after construction in `RootView`.
    public func attach(router: RootCoordinator) {
        self.coordinatorRouter = router
    }

    // MARK: - Lifecycle

    /// Open the SSE stream and start heartbeats. Idempotent — calling
    /// it again while a stream is already running is a no-op.
    public func startConnecting() {
        guard streamTask == nil else { return }

        state = .connecting
        connectionStatus = .connecting
        reconnectCount = 0

        let reconnector = makeReconnector()
        self.reconnector = reconnector
        let stream = reconnector.events()

        streamTask = Task { [weak self] in
            do {
                for try await event in stream {
                    guard let self else { return }
                    await self.handleSSEEvent(event)
                }
            } catch is CancellationError {
                // Caller cancelled — done.
            } catch {
                guard let self else { return }
                await self.handleStreamFatal(error: error)
            }
        }

        queueDrainTask?.cancel()
        queueDrainTask = Task { [queue, weak self] in
            // Drain any persisted offline scan results.
            let pending = await queue.drain { [weak self] count in
                Task { @MainActor in self?.pendingScanResultCount = count }
            }
            Task { @MainActor in self?.pendingScanResultCount = pending }
        }
    }

    /// Cancel the SSE stream and stop heartbeats. Called on
    /// backgrounding (`UIScene.willDeactivate`) or sign-out.
    public func stopConnecting() {
        streamTask?.cancel()
        streamTask = nil
        queueDrainTask?.cancel()
        queueDrainTask = nil
        reconnector = nil
        connectionStatus = .offline
        if case .connecting = state { state = .idle }
        if case .readyToScan = state { state = .idle }
    }

    // MARK: - Incoming scan requests (push + SSE)

    /// Coalesces an incoming scan request from either delivery channel.
    /// First arrival wins; subsequent arrivals for the same `pairingCode`
    /// inside the 90 s window are ignored.
    public func handleIncomingScanRequest(
        _ request: ScanRequest,
        source: ScanRequestSource
    ) {
        // Sweep stale entries first (cheap; map is at most ~10 entries).
        let cutoff = now().addingTimeInterval(-Self.pairingCoalesceWindow)
        recentPairings = recentPairings.filter { $0.value > cutoff }

        if recentPairings[request.pairingCode] != nil {
            return // Coalesced: already handled within the window.
        }
        recentPairings[request.pairingCode] = now()
        persistRecentPairings()

        // Drop if the request has already expired on arrival.
        let nowMs = Int64(now().timeIntervalSince1970 * 1000)
        if request.expiresAtEpochMs <= nowMs {
            state = .error(.pairingExpired)
            return
        }

        armedAt = now()
        state = .scanRequested(request)

        // Auto-fire the iOS NFC reader sheet so it acts as the primary
        // scan UI. The user no longer has to tap a "Tap to scan" button
        // — the request arriving IS the prompt, and dismissing the
        // sheet (system-Cancel inside it) is now the canonical cancel
        // affordance, propagated to the admin via
        // `cancelActiveScan` → `/api/devices/scan-cancel`. Skipping the
        // intermediate `.scanRequested` UI keeps the active screen's
        // visible bits (countdown ring + arrow indicator) co-located
        // with what iOS already shows.
        beginScan()
    }

    /// Drives the NFC session, signs the result, and POSTs. Invoked
    /// automatically from `handleIncomingScanRequest`; also kept
    /// public so a debug screen / future "retry" button can reuse it.
    public func beginScan() {
        guard case .scanRequested(let request) = state else { return }

        state = .scanning(request)

        Task { [weak self] in
            await self?.runScan(for: request)
        }
    }

    /// Manual cancel — returns to ready without surfacing an error AND
    /// notifies the server so the admin's in-flight TapToAddModal
    /// closes immediately. Handles both the pre-NFC `.scanRequested`
    /// state (legacy "Tap to scan" button) and the active-NFC
    /// `.scanning` state (auto-fired NFC sheet, plus the iOS-supplied
    /// Cancel chrome inside that sheet — see
    /// `runScan`'s `.userCanceled` branch). When `.scanning`, the NFC
    /// session is invalidated explicitly so the iOS sheet dismisses
    /// even when the cancel originates outside the sheet (e.g. a web
    /// `event: cancelled` SSE event).
    ///
    /// The local state flip happens synchronously; the
    /// `/api/devices/scan-cancel` POST is fire-and-forget so a
    /// transient network blip can't trap the user on the active
    /// screen.
    public func cancelActiveScan() {
        let pairingCode: String?
        switch state {
        case .scanRequested(let request):
            pairingCode = request.pairingCode
        case .scanning(let request):
            pairingCode = request.pairingCode
            // Force-dismiss the iOS NFC sheet. Safe even when called
            // from inside `runScan`'s `.userCanceled` branch (the
            // continuation is already nil by then).
            nfc.cancel()
        default:
            return
        }
        state = .readyToScan
        armedAt = nil

        guard let pairingCode else { return }
        Task { [environment] in
            let body = ScanCancelRequest(pairingCode: pairingCode)
            let endpoint = Endpoint.with(
                path: "/api/devices/scan-cancel",
                method: .post,
                requiresAuth: true,
                body: body
            )
            // Best-effort. Server-side cleanup is also covered by the
            // 90 s pairing TTL — if this POST fails, the admin modal will
            // still drop after the TTL window. We don't surface errors
            // because the user already sees their local state cleared.
            _ = try? await environment.api.send(endpoint)
        }
    }

    /// Manually dismiss a `.success` or `.error` screen back to ready.
    /// Per the HIG audit there is NO auto-return.
    public func dismissResult() {
        switch state {
        case .success, .error:
            state = connectionStatus == .online ? .readyToScan : .offline
        default:
            break
        }
        armedAt = nil
    }

    // MARK: - Submit pipeline

    private func runScan(for request: ScanRequest) async {
        do {
            let scan = try await nfc.scan(
                timeoutSeconds: 60,
                alertMessage: "Hold your card to the top of your iPhone."
            )
            await submitScan(idTag: scan.idTag, pairingCode: request.pairingCode)
        } catch let nfcError as NFCError {
            await MainActor.run {
                switch nfcError {
                case .timeout:
                    state = .error(.timeout)
                case .mifareClassicUnsupported, .unsupportedTag:
                    state = .error(.unsupportedCard)
                case .userCanceled:
                    // The user dismissed the iOS NFC reader sheet —
                    // treat as a full scan cancel so the admin's
                    // TapToAddModal closes too. `cancelActiveScan`
                    // also invalidates the NFC session, but the
                    // continuation is already nil here so that's a
                    // no-op.
                    cancelActiveScan()
                    return
                case .systemUnavailable, .underlying:
                    state = .error(.network)
                }
                armedAt = nil
            }
        } catch {
            await MainActor.run {
                state = .error(.network)
                armedAt = nil
            }
        }
    }

    /// Public for the diagnostics "Test scan" button + tests.
    public func submitScan(idTag: String, pairingCode: String) async {
        // Load the secret + deviceId. `loadCredentials()` triggers the
        // biometric prompt for the secret on a real device.
        let credentials: Credentials
        do {
            guard let creds = try await environment.authStore.loadCredentials() else {
                await MainActor.run {
                    state = .error(.tokenRevoked)
                }
                return
            }
            credentials = creds
        } catch {
            await MainActor.run { state = .error(.tokenRevoked) }
            return
        }

        let signer: ScanResultSigner
        do {
            signer = try ScanResultSigner(
                deviceSecretBase64URL: credentials.deviceSecret
            )
        } catch {
            await MainActor.run { state = .error(.server(code: "signer_init")) }
            return
        }

        let ts = Int64(now().timeIntervalSince1970)
        let nonce = signer.sign(
            idTag: idTag,
            pairingCode: pairingCode,
            deviceId: credentials.deviceId,
            ts: ts
        )

        let body = ScanResultRequest(
            idTag: idTag,
            pairingCode: pairingCode,
            ts: ts,
            nonce: nonce
        )
        let endpoint = Endpoint.with(
            path: "/api/devices/scan-result",
            method: .post,
            requiresAuth: true,
            body: body
        )

        do {
            let result: EnrichedScanResult = try await environment.api.request(endpoint)
            await MainActor.run {
                state = .success(result)
                armedAt = nil
            }
        } catch APIError.network {
            // Persist to the offline queue and surface a soft toast.
            await queue.enqueue(body: body)
            let count = await queue.count()
            await MainActor.run {
                state = .error(.network)
                pendingScanResultCount = count
                armedAt = nil
            }
        } catch APIError.unauthorized, APIError.invalidNonce {
            await handleTokenRevoked()
        } catch APIError.gone, APIError.rateLimited {
            await MainActor.run {
                state = .error(.pairingExpired)
                armedAt = nil
            }
        } catch APIError.clockSkew {
            await MainActor.run {
                state = .error(.server(code: "clock_skew"))
                armedAt = nil
            }
        } catch let api as APIError {
            await MainActor.run {
                if case .server(_, let code) = api {
                    state = .error(.server(code: code))
                } else {
                    state = .error(.server(code: nil))
                }
                armedAt = nil
            }
        } catch {
            await MainActor.run {
                state = .error(.network)
                armedAt = nil
            }
        }
    }

    // MARK: - Token revoke handling

    /// Wipes the keychain and routes back to `.welcome`. Surfaces a
    /// toast so the user knows why they were signed out.
    public func handleTokenRevoked() async {
        try? await environment.authStore.deleteAll()
        await MainActor.run {
            self.transientToast = "Signed out by an admin."
            self.state = .error(.tokenRevoked)
            self.stopConnecting()
            self.coordinatorRouter?.didSignOut()
        }
    }

    /// Clears the transient toast after the UI displays it.
    public func clearToast() { transientToast = nil }

    // MARK: - SSE event handling

    private func handleSSEEvent(_ event: SSEEvent) async {
        switch event.event {
        case "connected":
            connectionStatus = .online
            deviceState?.noteSSEConnected()
            if case .connecting = state { state = .readyToScan }
            if case .offline = state { state = .readyToScan }

        case "device.capabilities.changed":
            // Slice G — refresh the live `DeviceState` envelope and the
            // capability cache; the SwiftUI shell re-renders within ~1s.
            deviceState?.handleCapabilitiesChanged()

        case "device.settings.changed":
            // Slice G — pull merged settings; SettingsStore is updated
            // inside the coordinator's refresh path.
            deviceState?.handleSettingsChanged()

        case "scan.requested":
            guard let data = event.data.data(using: .utf8) else { return }
            do {
                let request = try JSONDecoder().decode(ScanRequest.self, from: data)
                handleIncomingScanRequest(request, source: .sse)
            } catch {
                // Malformed scan request — log + swallow.
            }

        case "scan.cancelled":
            // Bidirectional cancel sync — the admin closed the
            // TapToAddModal (or another device session cancelled the
            // same scan via /api/devices/scan-cancel). Drop the active
            // request locally if its `pairingCode` matches; do not
            // surface an error (admin cancel is normal flow, not a
            // failure).
            guard let data = event.data.data(using: .utf8) else { return }
            let payload = try? JSONDecoder().decode(ScanCancelledPayload.self, from: data)
            let activePairingCode: String?
            switch state {
            case .scanRequested(let req): activePairingCode = req.pairingCode
            case .scanning(let req): activePairingCode = req.pairingCode
            default: return
            }
            if let payload, let active = activePairingCode,
               payload.pairingCode != active {
                // Cancel for a different pairing — ignore. Shouldn't
                // happen (server filters by deviceId), belt-and-braces.
                return
            }
            // If we're mid-NFC, dismiss the iOS reader sheet so the
            // user sees the cancel land instantly. Do this BEFORE
            // flipping state so the NFCService's continuation can
            // still see `.scanning` if it runs synchronously.
            if case .scanning = state {
                nfc.cancel()
            }
            state = .readyToScan
            armedAt = nil

        case "device.session.replaced":
            // Another device session took over; the SSE will close
            // shortly. Show "offline" until the user foregrounds again
            // (in which case startConnecting kicks back off).
            connectionStatus = .offline
            state = .offline

        case "device.token.revoked":
            await handleTokenRevoked()

        default:
            // Unknown event types are ignored per SSE spec.
            break
        }
    }

    private func handleStreamFatal(error: Error) async {
        if case EventStreamError.unauthorized = error {
            await handleTokenRevoked()
            return
        }
        if case EventStreamError.gone = error {
            await handleTokenRevoked()
            return
        }
        // The reconnector itself does the loop; if we got here it
        // surfaced a non-recoverable cancellation.
        connectionStatus = .offline
        if case .scanRequested = state { return } // keep card visible
        state = .offline
    }

    // MARK: - Backgrounding hooks

    /// Called from `SceneDelegate.sceneDidEnterBackground` (E-app-wire
    /// will plug this in). Cancels the heartbeat task; SSE is left
    /// running until iOS suspends us.
    public func handleEnterBackground() {
        // Heartbeat is now driven by `DeviceStateCoordinator` and gets
        // its own background hook from `RootView`. Nothing scan-side
        // needs to suspend on background — the SSE link stays alive
        // until iOS suspends the app.
    }

    /// Called from `SceneDelegate.sceneWillEnterForeground`. Drains any
    /// queued scan results; the device-state sync is kicked separately
    /// by the parallel `DeviceStateCoordinator.handleEnterForeground()`
    /// call from `RootView`.
    public func handleEnterForeground() {
        Task { [queue, weak self] in
            let count = await queue.drain { [weak self] count in
                Task { @MainActor in self?.pendingScanResultCount = count }
            }
            Task { @MainActor in self?.pendingScanResultCount = count }
        }
    }

    // MARK: - Persistence helpers

    private func loadRecentPairings() {
        let defaults = UserDefaults.standard
        guard
            let raw = defaults.dictionary(forKey: Self.pairingCacheKey) as? [String: Double]
        else {
            return
        }
        let cutoff = now().addingTimeInterval(-Self.pairingCoalesceWindow)
        recentPairings = raw
            .compactMapValues { Date(timeIntervalSince1970: $0) }
            .filter { $0.value > cutoff }
    }

    private func persistRecentPairings() {
        let serialised = recentPairings.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(serialised, forKey: Self.pairingCacheKey)
    }
}

// MARK: - Reconnect-count plumbing

extension ScanCoordinator {
    /// Called from `EventStreamReconnector` whenever it schedules a
    /// retry. Wave-3 wireframes show a "Reconnecting…" pill in this
    /// state.
    public func noteReconnectAttempt() {
        reconnectCount += 1
        connectionStatus = .reconnecting
        deviceState?.noteReconnectAttempt()
    }
}
