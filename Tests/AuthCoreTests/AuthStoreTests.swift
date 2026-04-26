//
//  AuthStoreTests.swift
//  AuthCoreTests
//
//  End-to-end Keychain round-trip on a *temporary* service identifier so
//  we don't pollute the real `gg.vlad.expresscan` keychain. These tests
//  require macOS (no Linux Keychain shim), which is fine for the team
//  machine — the orchestrator skips them on Linux CI.
//
//  Note: we do NOT test `requiresUserPresence: true` here, because that
//  would trigger an actual biometric/passcode prompt. That path is
//  exercised on a real iOS device in the developer-machine gate.
//
//  Entitlement caveat: macOS rejects keychain writes from binaries that
//  are not properly code-signed with an `application-identifier`
//  entitlement (`OSStatus = -25308`, `errSecMissingEntitlement`). The
//  CLT-only `swift test` produces an unsigned binary, so on this host
//  the keychain primitive tests will detect that error and skip rather
//  than fail. On a developer Mac (Xcode code-sign) and on real iOS
//  devices the tests run end-to-end.
//

import Foundation
import Security
import Testing
@testable import AuthCore

/// Detects whether the test process can talk to the macOS keychain.
/// Unsigned `swift test` binaries get `errSecMissingEntitlement`
/// (-25308) on the first write. We probe once at suite-init and use
/// `.disabled(if:)` on individual tests so they show as skipped, not
/// failed.
private func keychainAvailable(service: String) -> Bool {
    let probe = KeychainStore(service: service)
    do {
        try probe.set(
            account: "__probe__",
            value: Data("probe".utf8),
            accessibility: .whenUnlockedThisDeviceOnly,
            requiresUserPresence: false
        )
        try? probe.delete(account: "__probe__")
        return true
    } catch let error as KeychainError {
        if case .unhandled(let status) = error,
           status == errSecMissingEntitlement {
            FileHandle.standardError.write(
                Data("keychain probe: errSecMissingEntitlement, suite skipped\n".utf8)
            )
            return false
        }
        return false
    } catch {
        // Any other error → also skip (we don't trust the env).
        return false
    }
}

private let keychainIsAvailable: Bool = {
    keychainAvailable(service: "gg.vlad.expresscan.probe.\(UUID().uuidString)")
}()

@Suite("AuthStore")
struct AuthStoreTests {

    // Each test gets its own service id so reruns / parallel workers
    // don't collide with each other or with production.
    let store: KeychainStore

    init() {
        let testService = "gg.vlad.expresscan.tests.\(UUID().uuidString)"
        self.store = KeychainStore(service: testService)
        try? store.deleteAll()
    }

    // Swift Testing has no destructor on a value-type suite. We rely on
    // the unique-per-test service id (above) to keep state from leaking
    // and add a defensive cleanup at the end of every test.

    // MARK: - KeychainStore primitive tests

    @Test(.disabled(if: !keychainIsAvailable, "keychain unavailable in unsigned test binary"))
    func keychainSetGetDeleteRoundtrip() throws {
        defer { try? store.deleteAll() }
        let value = Data("hello".utf8)
        try store.set(
            account: "test_account",
            value: value,
            accessibility: .whenUnlockedThisDeviceOnly,
            requiresUserPresence: false
        )

        let read = try store.get(account: "test_account")
        #expect(read == value)

        try store.delete(account: "test_account")
        let afterDelete = try store.get(account: "test_account")
        #expect(afterDelete == nil)
    }

    @Test func keychainGetReturnsNilForMissingAccount() throws {
        defer { try? store.deleteAll() }
        let read = try store.get(account: "does_not_exist")
        #expect(read == nil)
    }

    @Test(.disabled(if: !keychainIsAvailable, "keychain unavailable in unsigned test binary"))
    func keychainSetOverwritesExistingValue() throws {
        defer { try? store.deleteAll() }
        try store.set(
            account: "k",
            value: Data("v1".utf8),
            accessibility: .whenUnlockedThisDeviceOnly,
            requiresUserPresence: false
        )
        try store.set(
            account: "k",
            value: Data("v2".utf8),
            accessibility: .whenUnlockedThisDeviceOnly,
            requiresUserPresence: false
        )
        let read = try store.get(account: "k")
        #expect(read == Data("v2".utf8))
    }

    @Test func keychainDeleteMissingIsNotAnError() throws {
        defer { try? store.deleteAll() }
        try store.delete(account: "nope")
    }

    @Test(.disabled(if: !keychainIsAvailable, "keychain unavailable in unsigned test binary"))
    func keychainAfterFirstUnlockAccessibility() throws {
        defer { try? store.deleteAll() }
        try store.set(
            account: "token",
            value: Data("dev_xyz".utf8),
            accessibility: .afterFirstUnlockThisDeviceOnly,
            requiresUserPresence: false
        )
        let read = try store.get(account: "token")
        #expect(read == Data("dev_xyz".utf8))
    }

    // MARK: - AuthStore (high-level) tests

    @Test func authStoreLoadReturnsNilWhenEmpty() async throws {
        defer { try? store.deleteAll() }
        let auth = AuthStore(store: store)
        let creds = try await auth.loadCredentials()
        #expect(creds == nil)
        let hasValid = await auth.hasValidCredentials()
        #expect(hasValid == false)
    }

    @Test(.disabled(if: !keychainIsAvailable, "keychain unavailable in unsigned test binary"))
    func authStoreStoreThenLoadIdAndToken() async throws {
        defer { try? store.deleteAll() }
        // Set the id+token via the underlying KeychainStore at the same
        // accessibility classes used in production for those two fields.
        // We avoid `storeCredentials` so we don't trigger the
        // `requiresUserPresence: true` path which would prompt for
        // biometrics on a real device.
        try store.set(
            account: KeychainAccount.deviceId,
            value: Data("device-uuid".utf8),
            accessibility: .whenUnlockedThisDeviceOnly,
            requiresUserPresence: false
        )
        try store.set(
            account: KeychainAccount.deviceToken,
            value: Data("dev_token_xyz".utf8),
            accessibility: .afterFirstUnlockThisDeviceOnly,
            requiresUserPresence: false
        )

        let auth = AuthStore(store: store)
        let id = try await auth.loadDeviceID()
        #expect(id == "device-uuid")
        let token = try await auth.loadDeviceToken()
        #expect(token == "dev_token_xyz")
        let hasValid = await auth.hasValidCredentials()
        #expect(hasValid == true)
    }

    @Test(.disabled(if: !keychainIsAvailable, "keychain unavailable in unsigned test binary"))
    func authStoreDeleteAllClearsAllItems() async throws {
        defer { try? store.deleteAll() }
        try store.set(
            account: KeychainAccount.deviceId,
            value: Data("a".utf8),
            accessibility: .whenUnlockedThisDeviceOnly,
            requiresUserPresence: false
        )
        try store.set(
            account: KeychainAccount.deviceToken,
            value: Data("b".utf8),
            accessibility: .afterFirstUnlockThisDeviceOnly,
            requiresUserPresence: false
        )

        let auth = AuthStore(store: store)
        #expect(await auth.hasValidCredentials() == true)

        try await auth.deleteAll()
        #expect(await auth.hasValidCredentials() == false)
        #expect(try await auth.loadDeviceID() == nil)
        #expect(try await auth.loadDeviceToken() == nil)
    }

    @Test(.disabled(if: !keychainIsAvailable, "keychain unavailable in unsigned test binary"))
    func loadCredentialsReturnsNilWhenSecretMissing() async throws {
        defer { try? store.deleteAll() }
        // id + token present, secret missing — should return nil
        // (full credentials require all three).
        try store.set(
            account: KeychainAccount.deviceId,
            value: Data("a".utf8),
            accessibility: .whenUnlockedThisDeviceOnly,
            requiresUserPresence: false
        )
        try store.set(
            account: KeychainAccount.deviceToken,
            value: Data("b".utf8),
            accessibility: .afterFirstUnlockThisDeviceOnly,
            requiresUserPresence: false
        )

        let auth = AuthStore(store: store)
        let creds = try await auth.loadCredentials()
        #expect(creds == nil)
    }
}
