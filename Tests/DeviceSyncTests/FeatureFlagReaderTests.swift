//
//  FeatureFlagReaderTests.swift
//  DeviceSyncTests
//
//  Behavioural coverage for the typed-read fallbacks on
//  `FeatureFlagReader`. Defaults are returned both when the key is
//  missing and when the JSON value's type doesn't match the requested
//  read.
//

import Foundation
import Testing

@testable import DeviceSync

@Suite("FeatureFlagReader")
struct FeatureFlagReaderTests {

    private func entry(_ value: AnyCodableJSON) -> DeviceSettingValue {
        DeviceSettingValue(value: value, updatedAt: Date(), updatedBy: "admin")
    }

    @MainActor
    @Test func defaultsWhenKeyMissing() {
        let r = FeatureFlagReader()
        #expect(r.bool("missing", default: true) == true)
        #expect(r.bool("missing", default: false) == false)
        #expect(r.string("missing", default: "fallback") == "fallback")
        #expect(r.int("missing", default: 42) == 42)
        #expect(r.double("missing", default: 3.5) == 3.5)
    }

    @MainActor
    @Test func defaultsOnTypeMismatch() {
        let r = FeatureFlagReader()
        r.update([
            "k.string": entry(.string("hello")),
            "k.bool": entry(.bool(true)),
        ])
        // Asking for bool on a string-valued flag returns the default.
        #expect(r.bool("k.string", default: false) == false)
        // Asking for string on a bool-valued flag returns the default.
        #expect(r.string("k.bool", default: "fb") == "fb")
        // int/double on a string-valued flag returns the default.
        #expect(r.int("k.string", default: 7) == 7)
        #expect(r.double("k.string", default: 1.5) == 1.5)
    }

    @MainActor
    @Test func typedReadsAfterUpdate() {
        let r = FeatureFlagReader()
        r.update([
            "ff.bool": entry(.bool(true)),
            "ff.string": entry(.string("on")),
            "ff.int": entry(.int(99)),
            "ff.double": entry(.double(2.75)),
            // Numeric coercion: int <-> double is allowed on the
            // typed reads to avoid surprises with JSON's lack of
            // distinct integer/float types in some servers.
            "ff.intAsDouble": entry(.double(12.0)),
            "ff.doubleAsInt": entry(.int(7)),
        ])
        #expect(r.bool("ff.bool", default: false) == true)
        #expect(r.string("ff.string", default: "off") == "on")
        #expect(r.int("ff.int", default: 0) == 99)
        #expect(r.double("ff.double", default: 0) == 2.75)
        #expect(r.int("ff.intAsDouble", default: 0) == 12)
        #expect(r.double("ff.doubleAsInt", default: 0) == 7.0)
    }
}
