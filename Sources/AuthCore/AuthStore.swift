//
//  AuthStore.swift
//  AuthCore
//
//  Actor-isolated owner of the device's three Keychain items. All reads /
//  writes go through here so concurrent callers don't race.
//
//  Spec: `50-ios.md` § "Auth & registration flow" + `60-security.md` § 2.
//

import Foundation

/// The three pieces of data the iOS app holds after a successful
/// registration. All values are `String` (no PII).
public struct Credentials: Sendable, Equatable {
    public let deviceId: String
    public let deviceToken: String
    public let deviceSecret: String

    public init(deviceId: String, deviceToken: String, deviceSecret: String) {
        self.deviceId = deviceId
        self.deviceToken = deviceToken
        self.deviceSecret = deviceSecret
    }
}

/// Account names used in the keychain. Public so other modules / tests
/// can reference them.
public enum KeychainAccount {
    public static let deviceId = "deviceId"
    public static let deviceToken = "deviceToken"
    public static let deviceSecret = "deviceSecret"
}

/// Actor that serialises Keychain access for the device's credentials.
public actor AuthStore {

    private let store: KeychainStore

    public init(store: KeychainStore = .production) {
        self.store = store
    }

    /// Reads all three items and returns a `Credentials`, or `nil` if any
    /// are missing. Reading the secret will trigger a Face ID / passcode
    /// prompt on a real device — callers MUST be prepared for that.
    public func loadCredentials() throws -> Credentials? {
        guard
            let idData = try store.get(account: KeychainAccount.deviceId),
            let tokenData = try store.get(account: KeychainAccount.deviceToken),
            let secretData = try store.get(account: KeychainAccount.deviceSecret),
            let deviceId = String(data: idData, encoding: .utf8),
            let deviceToken = String(data: tokenData, encoding: .utf8),
            let deviceSecret = String(data: secretData, encoding: .utf8)
        else {
            return nil
        }
        return Credentials(
            deviceId: deviceId,
            deviceToken: deviceToken,
            deviceSecret: deviceSecret
        )
    }

    /// Writes (or replaces) all three credentials with the appropriate
    /// accessibility classes per `60-security.md` § 2.
    public func storeCredentials(
        deviceId: String,
        deviceToken: String,
        deviceSecret: String
    ) throws {
        // deviceId: whenUnlockedThisDeviceOnly, no user presence.
        try store.set(
            account: KeychainAccount.deviceId,
            value: Data(deviceId.utf8),
            accessibility: .whenUnlockedThisDeviceOnly,
            requiresUserPresence: false
        )

        // deviceToken: afterFirstUnlockThisDeviceOnly (background heartbeat).
        try store.set(
            account: KeychainAccount.deviceToken,
            value: Data(deviceToken.utf8),
            accessibility: .afterFirstUnlockThisDeviceOnly,
            requiresUserPresence: false
        )

        // deviceSecret: whenUnlockedThisDeviceOnly + user presence.
        try store.set(
            account: KeychainAccount.deviceSecret,
            value: Data(deviceSecret.utf8),
            accessibility: .whenUnlockedThisDeviceOnly,
            requiresUserPresence: true
        )
    }

    /// Convenience: cheap "are we registered" check. Looks for the
    /// `deviceToken` only (the lookup that *doesn't* trigger biometrics)
    /// to avoid surprising the user.
    public func hasValidCredentials() -> Bool {
        // `try?` collapses the throw → nil; an outer `guard let` then
        // distinguishes "lookup failed or returned nil" from "found".
        guard
            let data = (try? store.get(account: KeychainAccount.deviceToken)) ?? nil
        else {
            return false
        }
        return !data.isEmpty
    }

    /// Bulk-deletes all three items. Used by sign-out and by
    /// `device.token.revoked` handling.
    public func deleteAll() throws {
        try store.deleteAll()
    }

    // MARK: - Single-field reads

    /// Reads `deviceToken` only. Doesn't trigger biometrics. Used by the
    /// network layer's token-source closure.
    public func loadDeviceToken() throws -> String? {
        guard let data = try store.get(account: KeychainAccount.deviceToken) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Reads `deviceId` only. Doesn't trigger biometrics.
    public func loadDeviceID() throws -> String? {
        guard let data = try store.get(account: KeychainAccount.deviceId) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Reads `deviceSecret` only. **Triggers biometrics on a real device.**
    public func loadDeviceSecret() throws -> String? {
        guard let data = try store.get(account: KeychainAccount.deviceSecret) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
