//
//  DeviceStateCoordinatorTests.swift
//  ExpresScanTests
//
//  Wave 6 / Slice G. Tests the cold-launch cache fallback, the
//  consolidated sync flow, the SSE-driven refresh, foreground/background
//  cadence, and the soft-deleted-device 410 → revocation route.
//

import XCTest
@testable import ExpresScan
import AuthCore
import Capabilities
import DeviceSync
import Models
import Networking

@MainActor
final class DeviceStateCoordinatorTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() async throws {
        StubURLProtocol.reset()
        try await super.tearDown()
    }

    // MARK: - Cold launch / cache fallback

    func testColdLaunchSurfacesCachedCapabilitiesBeforeNetwork() {
        let defaults = makeIsolatedDefaults()
        let cache = CapabilityCache(defaults: defaults)
        // Pre-seed the cache with `[.user]` only — the previous
        // session's known-good capability set.
        cache.write([.user])

        let api = makeStubAPI(handler: nil) // never called in this test
        let store = try! makeIsolatedStore()
        let dsc = DeviceStateCoordinator(
            api: api,
            settingsStore: store,
            cache: cache,
            diagnosticsProvider: { Self.fakeDiagnostics() }
        )
        // Before bootstrap, the surface should be the cached set.
        XCTAssertEqual(dsc.capabilities, [.user])
        XCTAssertNil(dsc.state)
    }

    func testNoCacheFallsBackToRegistrationDefault() {
        let defaults = makeIsolatedDefaults() // empty
        let cache = CapabilityCache(defaults: defaults)
        let api = makeStubAPI(handler: nil)
        let store = try! makeIsolatedStore()
        let dsc = DeviceStateCoordinator(
            api: api,
            settingsStore: store,
            cache: cache,
            diagnosticsProvider: { Self.fakeDiagnostics() }
        )
        XCTAssertEqual(dsc.capabilities, DeviceStateCoordinator.defaultCapabilities)
    }

    // MARK: - Sync loop body

    func testSyncOnceFlushesPendingSettings() async throws {
        let defaults = makeIsolatedDefaults()
        let cache = CapabilityCache(defaults: defaults)
        let store = try makeIsolatedStore()
        // Seed pending setting so the coordinator's sync POST has
        // something to flush.
        try await store.setLocal(key: "device.label", value: .string("v"))

        // Capture the POST body to assert on.
        let captured = ConfinedBox<Data>()
        StubURLProtocol.handler = { request in
            if let body = bodyData(from: request) {
                captured.set(body)
            }
            return (200, ["Content-Type": "application/json"], envelopeJSON(capabilities: [.scanner]))
        }
        let api = makeStubAPI(handler: nil)
        let dsc = DeviceStateCoordinator(
            api: api,
            settingsStore: store,
            cache: cache,
            diagnosticsProvider: { Self.fakeDiagnostics() }
        )
        let ok = await dsc.syncOnce()
        XCTAssertTrue(ok)
        XCTAssertNotNil(dsc.state)
        XCTAssertEqual(dsc.connectionStatus, .online)
        XCTAssertEqual(dsc.capabilities, [.scanner])

        // Assert the flushed POST body had our pending key.
        let body = try XCTUnwrap(captured.get())
        let bodyString = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(bodyString.contains("device.label"),
                      "Expected POST body to contain pending setting key. Body: \(bodyString)")
    }

    func testSyncWritesCacheOnSuccess() async throws {
        let defaults = makeIsolatedDefaults()
        let cache = CapabilityCache(defaults: defaults)
        let store = try makeIsolatedStore()
        StubURLProtocol.handler = { _ in
            (200, ["Content-Type": "application/json"], envelopeJSON(capabilities: [.scanner, .user]))
        }
        let api = makeStubAPI(handler: nil)
        let dsc = DeviceStateCoordinator(
            api: api,
            settingsStore: store,
            cache: cache,
            diagnosticsProvider: { Self.fakeDiagnostics() }
        )
        _ = await dsc.syncOnce()
        XCTAssertEqual(cache.read(), [.scanner, .user])
    }

    func testSyncAppliesMergedSettingsToStore() async throws {
        let defaults = makeIsolatedDefaults()
        let cache = CapabilityCache(defaults: defaults)
        let store = try makeIsolatedStore()
        // Local pending edit — should be replaced after merge.
        try await store.setLocal(key: "device.label", value: .string("local"))
        StubURLProtocol.handler = { _ in
            (200, ["Content-Type": "application/json"], envelopeJSONWithSettings([
                "device.label": ("server-value", "admin"),
            ]))
        }
        let api = makeStubAPI(handler: nil)
        let dsc = DeviceStateCoordinator(
            api: api,
            settingsStore: store,
            cache: cache,
            diagnosticsProvider: { Self.fakeDiagnostics() }
        )
        _ = await dsc.syncOnce()
        let values = try await store.allValues()
        XCTAssertEqual(values["device.label"]?.value, .string("server-value"))
        let dirty = try await store.dirty()
        XCTAssertTrue(dirty.isEmpty)
    }

    // MARK: - SSE event routing

    func testCapabilitiesChangedTriggersRefresh() async throws {
        let defaults = makeIsolatedDefaults()
        let cache = CapabilityCache(defaults: defaults)
        let store = try makeIsolatedStore()
        let callCount = ConfinedBox<Int>()
        callCount.set(0)
        StubURLProtocol.handler = { _ in
            callCount.set((callCount.get() ?? 0) + 1)
            return (200, ["Content-Type": "application/json"], envelopeJSON(capabilities: [.user]))
        }
        let api = makeStubAPI(handler: nil)
        let dsc = DeviceStateCoordinator(
            api: api,
            settingsStore: store,
            cache: cache,
            diagnosticsProvider: { Self.fakeDiagnostics() }
        )
        dsc.handleCapabilitiesChanged()
        // Wait for the dispatched Task to run — give it a few hops.
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThanOrEqual(callCount.get() ?? 0, 1)
        XCTAssertEqual(dsc.capabilities, [.user])
    }

    func testSettingsChangedTriggersRefreshAndAppliesMerged() async throws {
        let defaults = makeIsolatedDefaults()
        let cache = CapabilityCache(defaults: defaults)
        let store = try makeIsolatedStore()
        StubURLProtocol.handler = { _ in
            (200, ["Content-Type": "application/json"], envelopeJSONWithSettings([
                "notifications.scanRequest": ("true", "admin"),
            ]))
        }
        let api = makeStubAPI(handler: nil)
        let dsc = DeviceStateCoordinator(
            api: api,
            settingsStore: store,
            cache: cache,
            diagnosticsProvider: { Self.fakeDiagnostics() }
        )
        dsc.handleSettingsChanged()
        try await Task.sleep(for: .milliseconds(100))
        let values = try await store.allValues()
        XCTAssertEqual(values["notifications.scanRequest"]?.value, .string("true"))
    }

    // MARK: - Soft-deleted / revocation

    func testGoneFromSyncTriggersRevocation() async throws {
        let defaults = makeIsolatedDefaults()
        let cache = CapabilityCache(defaults: defaults)
        cache.write([.scanner, .user])
        let store = try makeIsolatedStore()
        StubURLProtocol.handler = { _ in
            (410, [:], Data())
        }
        let api = makeStubAPI(handler: nil)
        let dsc = DeviceStateCoordinator(
            api: api,
            settingsStore: store,
            cache: cache,
            diagnosticsProvider: { Self.fakeDiagnostics() }
        )
        let ok = await dsc.syncOnce()
        XCTAssertFalse(ok)
        // Cache is cleared on revocation so the next user's cold launch
        // doesn't render the previous user's tabs.
        XCTAssertNil(cache.read())
        XCTAssertNil(dsc.state)
    }

    // MARK: - Foreground transition

    func testForegroundTransitionTriggersImmediateSync() async throws {
        let defaults = makeIsolatedDefaults()
        let cache = CapabilityCache(defaults: defaults)
        let store = try makeIsolatedStore()
        let calls = ConfinedBox<Int>()
        calls.set(0)
        StubURLProtocol.handler = { _ in
            calls.set((calls.get() ?? 0) + 1)
            return (200, ["Content-Type": "application/json"], envelopeJSON(capabilities: [.scanner]))
        }
        let api = makeStubAPI(handler: nil)
        let dsc = DeviceStateCoordinator(
            api: api,
            settingsStore: store,
            cache: cache,
            diagnosticsProvider: { Self.fakeDiagnostics() }
        )
        dsc.handleEnterBackground() // suspends cadence
        dsc.handleEnterForeground() // kicks immediate sync
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThanOrEqual(calls.get() ?? 0, 1)
    }

    // MARK: - Cancellation

    func testStopCancelsLoop() async throws {
        let defaults = makeIsolatedDefaults()
        let cache = CapabilityCache(defaults: defaults)
        let store = try makeIsolatedStore()
        StubURLProtocol.handler = { _ in
            (200, ["Content-Type": "application/json"], envelopeJSON(capabilities: [.scanner]))
        }
        let api = makeStubAPI(handler: nil)
        let dsc = DeviceStateCoordinator(
            api: api,
            settingsStore: store,
            cache: cache,
            diagnosticsProvider: { Self.fakeDiagnostics() }
        )
        dsc.bootstrap()
        try await Task.sleep(for: .milliseconds(50))
        dsc.stop()
        XCTAssertEqual(dsc.connectionStatus, .offline)
    }

    // MARK: - Helpers

    private static func fakeDiagnostics() -> SyncRequest.Diagnostics {
        SyncRequest.Diagnostics(
            appVersion: "1.0.0 (1)",
            osVersion: "26.0",
            model: "iPhone",
            pushPermission: .notDetermined,
            nfcAvailable: true,
            pendingUploads: 0,
            reconnectCount: 0
        )
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "DeviceStateCoordinatorTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    private func makeIsolatedStore() throws -> SettingsStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DSCTests-\(UUID().uuidString)", isDirectory: true)
        return try SettingsStore(directoryURL: dir)
    }

    private func makeStubAPI(handler: (@Sendable (URLRequest) -> (Int, [String: String], Data))?) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        if let handler {
            StubURLProtocol.handler = { req in handler(req) }
        }
        return APIClient(
            baseURL: URL(string: "https://example.test")!,
            transport: session,
            tokenSource: { "stub_token" },
            idempotencyKeyFactory: { "fixed-uuid" }
        )
    }
}

// MARK: - JSON envelope fixtures

private func envelopeJSON(capabilities: [DeviceCapability]) -> Data {
    let caps = capabilities.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
    let json = """
    {
      "device": {
        "id": "dev_test",
        "label": "Test iPhone",
        "kind": "phone_nfc",
        "ownerUserId": "usr_1",
        "siteId": null,
        "registeredAt": "2026-04-27T12:00:00Z",
        "lastSeenAt": "2026-04-27T12:00:00Z"
      },
      "capabilities": [\(caps)],
      "kioskAllowed": false,
      "ownerUser": { "id": "usr_1", "role": "admin", "displayName": "Test" },
      "settings": {},
      "scanStatus": null,
      "pushToken": null,
      "connectivity": { "online": true, "lastSyncAt": null, "reconnectCount": 0, "pendingUploads": 0 }
    }
    """
    return Data(json.utf8)
}

private func envelopeJSONWithSettings(_ entries: [String: (String, String)]) -> Data {
    var settings: [String] = []
    // `updatedAt` is encoded as ISO-8601 to match the APIClient decoder's
    // `dateDecodingStrategy = .iso8601` and the TS server's `toISOString()`.
    let updatedAt = "2023-11-14T22:13:20.000Z"
    for (key, (value, by)) in entries {
        settings.append(#""\#(key)": { "value": "\#(value)", "updatedAt": "\#(updatedAt)", "updatedBy": "\#(by)" }"#)
    }
    let settingsJSON = settings.joined(separator: ",")
    let json = """
    {
      "device": {
        "id": "dev_test",
        "label": "Test iPhone",
        "kind": "phone_nfc",
        "ownerUserId": "usr_1",
        "siteId": null,
        "registeredAt": "2026-04-27T12:00:00Z",
        "lastSeenAt": "2026-04-27T12:00:00Z"
      },
      "capabilities": ["scanner"],
      "kioskAllowed": false,
      "ownerUser": { "id": "usr_1", "role": "admin", "displayName": "Test" },
      "settings": { \(settingsJSON) },
      "scanStatus": null,
      "pushToken": null,
      "connectivity": { "online": true, "lastSyncAt": null, "reconnectCount": 0, "pendingUploads": 0 }
    }
    """
    return Data(json.utf8)
}

private func bodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    if let stream = request.httpBodyStream {
        var data = Data()
        stream.open()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        stream.close()
        return data.isEmpty ? nil : data
    }
    return nil
}

/// Minimal lock-protected box for capturing values out of the SSE stub
/// closure (which is `@Sendable`).
final class ConfinedBox<T>: @unchecked Sendable {
    private var value: T?
    private let lock = NSLock()
    func set(_ v: T) { lock.lock(); defer { lock.unlock() }; value = v }
    func get() -> T? { lock.lock(); defer { lock.unlock() }; return value }
}
