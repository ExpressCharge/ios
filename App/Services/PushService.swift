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

import Foundation

import AuthCore
import Models
import Networking

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

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    // MARK: - APNs token upload

    /// Persists the raw APNs token (base64) against the registered
    /// device. Idempotent; safe to call multiple times.
    public func uploadToken(_ base64Token: String) async {
        do {
            guard let deviceId = try await environment.authStore.loadDeviceID() else {
                // Pre-registration token receipt: stash for the
                // RegistrationViewModel to pick up.
                return
            }
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
        } catch {
            // Soft-fail: we'll retry on the next `didRegisterForRemoteNotificationsWithDeviceToken`
            // call, and the heartbeat path doesn't depend on this.
        }
    }

    // MARK: - APNs payload routing

    /// Decode an APNs payload `userInfo` dictionary into a
    /// `ScanRequest` and forward it to the coordinator. Silently
    /// returns on payloads that don't carry a scan request.
    public func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        guard let request = Self.decodeScanRequest(from: userInfo) else {
            return
        }
        coordinator?.handleIncomingScanRequest(request, source: .push)
    }

    /// Convert the canonical APNs payload (see `20-contracts.md`) into
    /// a `ScanRequest`. Returns `nil` if any required field is missing
    /// or malformed.
    static func decodeScanRequest(
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
                  let ms = Int64(s) {
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
            iso = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(expiresAtMs) / 1000))
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
