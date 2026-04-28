//
//  SettingsViewModel.swift
//  ExpresScan
//
//  View-model for the Settings sheet:
//
//   - Fetches `GET /api/devices/me` to populate the Account section.
//   - Owns the "Sign out" pipeline: `DELETE /api/devices/{deviceId}` is
//     called BEFORE the local Keychain wipe so the server-side row is
//     deleted while we still hold a valid bearer token. If the network
//     call fails (offline / 401 / 410) we still wipe local state so the
//     user can continue.
//   - Holds a placeholder `renameDeviceLocally(_:)` hook. Per
//     `50-ios.md` the public iOS API does not yet support an
//     owner-side rename; we surface the local edit as "stays on this
//     device" so users aren't blocked. The admin-side rename
//     (`POST /api/admin/devices/{id}/rename`) requires the cookie
//     session, which is out of scope for v1.
//
//  Spec:
//    - `50-ios.md` § "Settings screen"
//    - `50-ios.md` § "Sign-out = deregister"
//    - `20-contracts.md` § "GET /api/devices/me"
//

import Foundation
import Observation

import AuthCore
import Models
import Networking

/// Decoded body of `GET /api/devices/me`. Mirrors the TS shape; kept
/// view-model-local to avoid leaking the type into other modules until
/// it ossifies.
public struct DeviceMeResponse: Codable, Sendable, Equatable {
    public let deviceId: String
    public let label: String
    public let kind: String?
    public let ownerUserId: String?
    /// Server-rendered identity for the Account row. Falls back from
    /// `users.displayName` → `users.name` → `users.email` → null. Use
    /// this in the UI; `ownerName`/`ownerEmail` are exposed for
    /// row-by-row inspection in Diagnostics.
    public let ownerDisplayName: String?
    public let ownerName: String?
    public let ownerEmail: String?
    public let registeredAtIso: String?

    public init(
        deviceId: String,
        label: String,
        kind: String? = nil,
        ownerUserId: String? = nil,
        ownerDisplayName: String? = nil,
        ownerName: String? = nil,
        ownerEmail: String? = nil,
        registeredAtIso: String? = nil
    ) {
        self.deviceId = deviceId
        self.label = label
        self.kind = kind
        self.ownerUserId = ownerUserId
        self.ownerDisplayName = ownerDisplayName
        self.ownerName = ownerName
        self.ownerEmail = ownerEmail
        self.registeredAtIso = registeredAtIso
    }
}

@MainActor
@Observable
public final class SettingsViewModel {

    private let environment: AppEnvironment
    private weak var router: RootCoordinator?

    public private(set) var me: DeviceMeResponse?
    public private(set) var meIsLoading: Bool = false
    public private(set) var meError: String?

    public private(set) var isSigningOut: Bool = false
    public private(set) var signOutError: String?

    /// Local-only label edit. The renamed value is kept as the user
    /// types; calling `commitLocalRename()` writes it to UserDefaults
    /// so the next launch shows the user's preferred name.
    public var label: String

    public init(environment: AppEnvironment, router: RootCoordinator?) {
        self.environment = environment
        self.router = router
        self.label = UserDefaults.standard.string(forKey: Self.localLabelKey) ?? ""
    }

    private static let localLabelKey = "ExpresScan.LocalDeviceLabel"

    // MARK: - Account refresh

    public func refreshAccount() async {
        meIsLoading = true
        meError = nil
        defer { meIsLoading = false }

        let endpoint = Endpoint(
            path: "/api/devices/me",
            method: .get,
            requiresAuth: true
        )
        do {
            let response: DeviceMeResponse = try await environment.api.request(endpoint)
            me = response
            // If the server has a label and we don't, adopt it locally.
            if label.isEmpty {
                label = response.label
            }
        } catch APIError.unauthorized {
            meError = "Signed out by an admin."
            await router?.scan?.handleTokenRevoked()
        } catch APIError.network {
            meError = "Couldn't reach ExpresSync."
        } catch {
            meError = "Couldn't load account info."
        }
    }

    // MARK: - Sign out

    /// Calls `DELETE /api/devices/{id}` (with the current bearer
    /// token), then wipes the keychain and returns the user to
    /// `.welcome`. The sequence is deliberate: we want the server-side
    /// row gone while we still know the bearer token. If the DELETE
    /// fails for a transient reason, we still wipe local state — the
    /// alternative is leaving the device wedged in a sign-in loop.
    public func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        signOutError = nil
        defer { isSigningOut = false }

        do {
            if let deviceId = try await environment.authStore.loadDeviceID() {
                let endpoint = Endpoint(
                    path: "/api/devices/\(deviceId)",
                    method: .delete,
                    requiresAuth: true
                )
                do {
                    try await environment.api.send(endpoint)
                } catch APIError.unauthorized, APIError.notFound, APIError.gone {
                    // Server already considers us deregistered. Carry
                    // on with the local wipe.
                } catch APIError.network {
                    // Offline. We still wipe local state — see comment
                    // above. The server-side row will be GC'd by the
                    // device-token expiry sweep.
                    signOutError = "Signed out locally. We'll finish on the server next time you're online."
                } catch {
                    signOutError = "Server reported an error during sign-out."
                }
            }
        } catch {
            // Keychain read failure during a sign-out is non-fatal —
            // the deleteAll() below scrubs everything anyway.
        }

        // Always wipe local state.
        try? await environment.authStore.deleteAll()
        // Clear locally-cached label so re-register starts fresh.
        UserDefaults.standard.removeObject(forKey: Self.localLabelKey)

        router?.didSignOut()
    }

    // MARK: - Local rename

    /// Persists the current `label` to UserDefaults so the home screen
    /// + future Account sheet show the user's preferred name. The
    /// admin-side rename endpoint is gated on a cookie session and is
    /// not exposed here in v1; the developer Mac milestone tracks a
    /// follow-up.
    public func commitLocalRename() {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.localLabelKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: Self.localLabelKey)
        }
    }
}
