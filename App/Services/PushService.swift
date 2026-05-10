//
//  PushService.swift
//  ExpresScan
//
//  Typed APNs payload decoder + token-registration shipper. Replaces
//  the `AppNotifications.scanRequestPushReceived` NotificationCenter
//  handoff in `AppDelegate.swift` with a strongly-typed pipeline:
//
//      AppDelegate → PushService.handleRemoteNotification(...)
//                  → ScanCoordinator.handleIncomingScanRequest(...)
//
//  Plus a small upload helper for the APNs token:
//
//      AppDelegate → PushService.uploadToken(...) →
//        POST /api/devices/{id}/push-token
//
//  Spec:
//    - `50-ios.md` § "Push handling"
//    - `20-contracts.md` § "APNs payload (canonical)"
//    - `20-contracts.md` § "PUT /api/devices/{deviceId}/push-token"
//

import AuthCore
import Foundation
import Models
import Networking
import UIKit

/// Errors emitted by the push service. All non-fatal — the token-upload
/// path retries opportunistically, payload decode failures are
/// swallowed (we don't want a malformed push to wedge the app).
public enum PushServiceError: Error, Equatable, Sendable {
    case missingDeviceId
    case decodingFailed
    case uploadFailed
}

@MainActor
public final class PushService {

    private let environment: AppEnvironment
    /// Bound by `RootView` after construction.
    public weak var coordinator: ScanCoordinator?
    /// Bound by `RootView` after `ensureDeviceStateCoordinator(...)`.
    /// Used by the Phase 2b `device.locate` silent-push handler to
    /// trigger an on-demand sync after the cache writes.
    public weak var deviceState: DeviceStateCoordinator?

    /// Last APNs token observed by this process — set on every
    /// `uploadToken(_:)` call regardless of whether the PUT lands.
    /// Used by `refreshIfAuthenticated()` to drain a stashed token
    /// once `deviceId` becomes available (covers the race where iOS
    /// delivered the token before registration completed).
    private var pendingToken: String?
    /// Last token successfully PUT to the server. Used to skip
    /// redundant uploads when iOS redelivers the same token on
    /// cold-launch.
    private var lastUploadedToken: String?

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    // MARK: - APNs token upload

    /// Persists the raw APNs token (base64) against the registered
    /// device. Idempotent; safe to call multiple times.
    public func uploadToken(_ base64Token: String) async {
        guard !base64Token.isEmpty else {
            authLog.error("PushService.uploadToken: empty token, refusing to upload")
            return
        }
        pendingToken = base64Token
        if base64Token == lastUploadedToken {
            authLog.debug("PushService.uploadToken: token unchanged, skip PUT")
            return
        }
        do {
            guard let deviceId = try await environment.authStore.loadDeviceID() else {
                // Pre-registration token receipt: stashed in
                // `pendingToken`; `refreshIfAuthenticated()` drains it
                // after credentials land.
                authLog.debug(
                    "PushService.uploadToken: deferred — no deviceId yet (token.len=\(base64Token.count))"
                )
                return
            }
            let env = BuildConfig.apnsEnvironment == "production" ? "production" : "sandbox"
            authLog.debug(
                "PushService.uploadToken: PUT /api/devices/\(deviceId, privacy: .public)/push-token env=\(env, privacy: .public) token.len=\(base64Token.count)"
            )
            let body = PushTokenUpdateRequest(
                pushToken: base64Token,
                apnsEnvironment: BuildConfig.apnsEnvironment == "production"
                    ? .production : .sandbox
            )
            let endpoint = Endpoint.with(
                path: "/api/devices/\(deviceId)/push-token",
                method: .put,
                requiresAuth: true,
                body: body
            )
            try await environment.api.send(endpoint)
            lastUploadedToken = base64Token
            authLog.debug(
                "PushService.uploadToken: PUT succeeded (deviceId=\(deviceId, privacy: .public))"
            )
        } catch {
            // Soft-fail: we'll retry on the next
            // `didRegisterForRemoteNotificationsWithDeviceToken` call
            // or the next `refreshIfAuthenticated()` from bootstrap.
            authLog.error(
                "PushService.uploadToken: PUT failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Called from `RootCoordinator.bootstrap()` whenever we transition
    /// into `.ready` with valid credentials. Pokes iOS to redeliver
    /// the APNs token via `AppDelegate.didRegisterForRemoteNotifications`
    /// AND drains any token already stashed in `pendingToken` (covers
    /// the race where iOS delivered before sign-in completed). Either
    /// path lands the same effect: PUT with the current token.
    public func refreshIfAuthenticated() {
        UIApplication.shared.registerForRemoteNotifications()
        if let token = pendingToken {
            authLog.debug(
                "PushService.refreshIfAuthenticated: draining stashed token (len=\(token.count))"
            )
            Task { await self.uploadToken(token) }
        }
    }

    // MARK: - APNs payload routing

    /// Decode an APNs payload `userInfo` dictionary and dispatch on
    /// the typed `type` field (Phase 2b). Falls back to the legacy
    /// scan-request path for payloads without a `type` (the original
    /// scan-arm flow). Silently returns on unrecognised payloads.
    public func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        // Phase 2b — typed dispatch. The `type` field is set by
        // `routes/api/admin/devices/[id]/locate.ts`; older scan-arm
        // pushes don't carry it and fall through to the legacy path.
        if let type = userInfo["type"] as? String {
            handleTypedPush(type: type, userInfo: userInfo)
            return
        }
        guard let request = Self.decodeScanRequest(from: userInfo) else {
            return
        }
        coordinator?.handleIncomingScanRequest(request, source: .push)
    }

    /// Typed-payload dispatch. Add new branches as new push types land.
    private func handleTypedPush(
        type: String,
        userInfo: [AnyHashable: Any]
    ) {
        switch type {
        case "device.locate":
            handleLocatePush(userInfo: userInfo)
        default:
            // Unknown type — log once but don't crash. Newer servers
            // may send types older clients haven't learned yet.
            authLog.debug(
                "PushService.handleRemoteNotification: unknown type '\(type, privacy: .public)' — ignored"
            )
        }
    }

    /// Phase 2 Bundle 2b — silent "Locate now" push. Trigger a one-shot
    /// `requestLocation()` on the managed-location cache, then force a
    /// sync so the new fix flushes server-side immediately.
    ///
    /// The push payload carries a `correlationId` we'd echo back if we
    /// had a fast-path SSE event for the location update; today the
    /// admin UI just polls the device row's `last_location_at` after
    /// posting Locate-now. The correlationId is read for completeness
    /// in case we add an `expresscharge.locate.completed` SSE later.
    private func handleLocatePush(userInfo: [AnyHashable: Any]) {
        let correlationId = userInfo["correlationId"] as? String ?? "<unknown>"
        authLog.debug(
            "PushService: device.locate received (correlationId=\(correlationId, privacy: .public))"
        )
        let cache = environment.managedLocationCache
        let coordinator = deviceState
        Task { @MainActor in
            _ = await cache.requestOneShot(
                reason: ManagedLocationOneShotReason.silentPushLocate
            )
            await coordinator?.syncOnce()
        }
    }

    /// Convert the canonical APNs payload (see `20-contracts.md`) into
    /// a `ScanRequest`. Returns `nil` if any required field is missing
    /// or malformed.
    ///
    /// `nonisolated` because the function is pure (no `self` access)
    /// and we want to call it from unit tests that don't run on
    /// `@MainActor`.
    nonisolated static func decodeScanRequest(
        from userInfo: [AnyHashable: Any]
    ) -> ScanRequest? {
        guard
            let deviceId = userInfo["deviceId"] as? String,
            let pairingCode = userInfo["pairingCode"] as? String,
            let purposeRaw = userInfo["purpose"] as? String,
            let purpose = ScanPurpose(rawValue: purposeRaw)
        else {
            return nil
        }

        // expiresAt may arrive as a Number (NSNumber bridged to Int64)
        // or as a String — defensive on both paths.
        let expiresAtMs: Int64
        if let n = userInfo["expiresAtEpochMs"] as? NSNumber {
            expiresAtMs = n.int64Value
        } else if let s = userInfo["expiresAtEpochMs"] as? String,
            let ms = Int64(s)
        {
            expiresAtMs = ms
        } else {
            return nil
        }

        // ISO timestamp is best-effort — we don't use it for arming,
        // only for analytics. Synthesise it from epoch ms if absent.
        let iso: String
        if let s = userInfo["expiresAtIso"] as? String {
            iso = s
        } else {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            iso = formatter.string(
                from: Date(timeIntervalSince1970: TimeInterval(expiresAtMs) / 1000))
        }

        let hint = userInfo["hintLabel"] as? String
        let requestedBy = userInfo["requestedByUserId"] as? String

        return ScanRequest(
            deviceId: deviceId,
            pairingCode: pairingCode,
            purpose: purpose,
            expiresAtIso: iso,
            expiresAtEpochMs: expiresAtMs,
            requestedByUserId: requestedBy,
            hintLabel: hint
        )
    }
}
