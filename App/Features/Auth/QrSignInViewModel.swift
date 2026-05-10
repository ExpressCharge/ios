//
//  QrSignInViewModel.swift
//  ExpresScan
//
//  Track I7 — iOS-only QR sign-in. Driven by the
//  `AppNotifications.userQrSignInRequested` notification posted from
//  `RootView.handleUniversalLink` when the iPhone Camera resolves a
//  user-card sticker URL (`https://example.com/u/<publicId>`).
//
//  Flow:
//    1. ViewModel receives a publicId.
//    2. POSTs to `/api/auth/qr-sign-in` with the device-registration
//       metadata (label, platform, model, OS/app version, push token).
//    3. Server mints a customer session, registers the device, and
//       auto-binds a per-device OCPP tag in one round-trip.
//    4. ViewModel persists the device credentials in the Keychain via
//       `AuthStore.storeCredentials`.
//    5. The signed-in path (the existing tab container) takes over —
//       the device token in the Keychain is the signal, same as the
//       admin PKCE registration flow.
//
//  Trust model (server-side): the publicId is the bearer credential.
//  The iOS side just relays the URL the Camera resolved — there's no
//  PKCE handshake, no biometric gate. Friends-and-family scope.
//

import AuthCore
import Foundation
import Networking
import Observation
import UIKit

@MainActor
@Observable
public final class QrSignInViewModel {

    public enum LoadState: Equatable, Sendable {
        case idle
        case loading
        case ok
        /// `message` is the customer-friendly copy; `raw` carries the
        /// underlying `APIError` for the admin-only diagnostic block.
        case error(message: String, raw: APIError?)
    }

    public private(set) var loadState: LoadState = .idle

    private let api: APIClient
    private let authStore: AuthStore

    public init(api: APIClient, authStore: AuthStore) {
        self.api = api
        self.authStore = authStore
    }

    /// Process a publicId received from a universal-link / Camera scan.
    /// Returns true on success — the caller can then transition the
    /// app into the authenticated state. Errors are surfaced via
    /// `loadState`.
    @discardableResult
    public func signIn(publicId: String, pushToken: String? = nil) async -> Bool {
        if case .loading = loadState { return false }
        loadState = .loading

        let device = UIDevice.current
        let body = QrSignInRequest(
            userPublicId: publicId,
            deviceLabel: device.name.isEmpty
                ? "ExpresScan iPhone"
                : device.name,
            platform: "ios",
            model: device.model,
            osVersion: device.systemVersion,
            appVersion: BuildConfig.appVersion,
            pushToken: pushToken,
            apnsEnvironment: BuildConfig.apnsEnvironment
        )

        let endpoint = Endpoint.with(
            path: "/api/auth/qr-sign-in",
            method: .post,
            // No bearer yet — the publicId in the body is the
            // credential, and the endpoint is registered as PUBLIC
            // in the server's route classifier.
            requiresAuth: false,
            body: body
        )
        do {
            let response: QrSignInResponse = try await api.request(endpoint)
            try await authStore.storeCredentials(
                deviceId: response.device.id,
                deviceToken: response.token.deviceToken,
                deviceSecret: response.token.deviceSecret
            )
            loadState = .ok
            return true
        } catch let error as APIError {
            loadState = .error(message: message(for: error), raw: error)
            return false
        } catch {
            loadState = .error(
                message: "Couldn't sign in. Try scanning again.", raw: nil)
            return false
        }
    }

    private func message(for error: APIError) -> String {
        error.customerFacingMessage(in: .signIn)
    }
}

// MARK: - Wire types

private struct QrSignInRequest: Encodable {
    let userPublicId: String
    let deviceLabel: String
    let platform: String
    let model: String
    let osVersion: String
    let appVersion: String
    let pushToken: String?
    let apnsEnvironment: String
}

private struct QrSignInResponse: Decodable {
    let device: DeviceWire
    let token: TokenWire
    let user: UserWire

    struct DeviceWire: Decodable {
        let id: String
        let label: String
        let capabilities: [String]
        let ownerUserId: String
    }

    struct TokenWire: Decodable {
        let id: String
        let deviceToken: String
        let deviceSecret: String
        let expiresAt: String
    }

    struct UserWire: Decodable {
        let id: String
        let publicId: String
        let name: String?
        let email: String?
    }
}
