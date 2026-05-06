//
//  CapabilityCacheTests.swift
//  DeviceSyncTests
//
//  Round-trip persistence + nil-on-missing semantics for
//  `CapabilityCache`.
//

import Foundation
import Testing

@testable import DeviceSync
@testable import Models

@Suite("CapabilityCache — UserDefaults-backed persistence")
struct CapabilityCacheTests {

    /// Fresh isolated `UserDefaults` per test so we don't pollute the
    /// shared store and tests can run in parallel.
    private func makeDefaults() -> UserDefaults {
        let suite = "CapabilityCacheTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("UserDefaults(suiteName:) returned nil for \(suite)")
        }
        return defaults
    }

    @Test func missingKeyReturnsNil() {
        let cache = CapabilityCache(defaults: makeDefaults())
        #expect(cache.read() == nil)
    }

    @Test func writeReadRoundTrip() {
        let defaults = makeDefaults()
        let cache = CapabilityCache(defaults: defaults)
        let caps: Set<DeviceCapability> = [.scanner, .user]
        cache.write(caps)
        let loaded = cache.read()
        #expect(loaded == caps)
    }

    @Test func writeOverwrites() {
        let cache = CapabilityCache(defaults: makeDefaults())
        cache.write([.scanner])
        cache.write([.user, .kiosk])
        #expect(cache.read() == [.user, .kiosk])
    }

    @Test func emptySetIsRoundTripped() {
        let cache = CapabilityCache(defaults: makeDefaults())
        cache.write([])
        // An explicit empty set is distinguishable from "never written"
        // — the underlying UserDefaults stores an empty array.
        #expect(cache.read() == [])
    }

    @Test func clearErasesValue() {
        let cache = CapabilityCache(defaults: makeDefaults())
        cache.write([.scanner, .user])
        #expect(cache.read() != nil)
        cache.clear()
        #expect(cache.read() == nil)
    }

    @Test func unknownCapabilityRawValuesAreSkipped() {
        // Forward-compat: server may add a capability we don't know
        // about yet — we should ignore unknown rawValues, not crash.
        let defaults = makeDefaults()
        defaults.set(
            ["scanner", "future_unknown_cap", "user"],
            forKey: CapabilityCache.storageKey)
        let cache = CapabilityCache(defaults: defaults)
        #expect(cache.read() == [.scanner, .user])
    }

    @Test func separateCachesAreIsolated() {
        // Two caches with separate suite names should not see each
        // other's data — sanity check on the test harness.
        let a = CapabilityCache(defaults: makeDefaults())
        let b = CapabilityCache(defaults: makeDefaults())
        a.write([.scanner])
        #expect(b.read() == nil)
    }
}
