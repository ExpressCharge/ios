//
//  MagicEmailSignInViewModel.swift
//  ExpresScan
//
//  Plan B2 / task #8 — counterpart to `QrSignInViewModel` for the
//  magic-email customer login flow. Receives a token parsed from
//  `https://example.com/m/<token>`, POSTs it to
//  `/api/auth/magic-link/verify` (task #9, backend) with the same
//  device-registration metadata as the QR flow, persists the
//  `{device, token, user}` response into the Keychain, and drives a
//  `CustomerSignInPhase` for the parent progress view.
//
//  Mirrors `QrSignInViewModel.swift` line-by-line on purpose so the
//  diff is mechanically reviewable.
//

import AuthCore
import Foundation
import Networking
import Observation
import UIKit

@MainActor
@Observable
public final class MagicEmailSignInViewModel {

    /// Drives `CustomerSignInProgressView`. The router observes this
    /// and forwards the value into its `RootRoute.customerSigningIn`
    /// payload.
    public private(set) var phase: CustomerSignInPhase = .confirming

    private let api: APIClient
    private let authStore: AuthStore

    public init(api: APIClient, authStore: AuthStore) {
        self.api = api
        self.authStore = authStore
    }

    /// Verify a magic-link token and register this iPhone as a customer
    /// device. Returns `true` on success — the caller bootstraps the
    /// authenticated shell. Errors are surfaced via `phase`.
    @discardableResult
    public func signIn(token: String, pushToken: String? = nil) async -> Bool {
        phase = .confirming

        let device = UIDevice.current
        let body = MagicLinkVerifyRequest(
            token: token,
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
            path: "/api/auth/magic-link/verify",
            method: .post,
            // The magic-link token is the bearer credential; this
            // endpoint is registered as PUBLIC server-side.
            requiresAuth: false,
            body: body
        )
        do {
            let response: MagicLinkVerifyResponse = try await api.request(endpoint)
            phase = .registering
            try await authStore.storeCredentials(
                deviceId: response.device.id,
                deviceToken: response.token.deviceToken,
                deviceSecret: response.token.deviceSecret
            )
            phase = .finalizing
            return true
        } catch let error as APIError {
            phase = .failure(message: message(for: error))
            return false
        } catch {
            phase = .failure(
                message: "Couldn't sign in. Open the link from your email again."
            )
            return false
        }
    }

    private func message(for error: APIError) -> String {
        // Magic-link `.notFound` is more specific than the generic
        // sign-in default ("…check the QR isn't damaged" doesn't apply
        // when the user clicked an email link), so override that one
        // case before falling through to the central helper.
        if case .notFound = error {
            return "This sign-in link has expired. Request a new one from your email."
        }
        return error.customerFacingMessage(in: .signIn)
    }
}

// MARK: - Wire types

private struct MagicLinkVerifyRequest: Encodable {
    let token: String
    let deviceLabel: String
    let platform: String
    let model: String
    let osVersion: String
    let appVersion: String
    let pushToken: String?
    let apnsEnvironment: String
}

private struct MagicLinkVerifyResponse: Decodable {
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
