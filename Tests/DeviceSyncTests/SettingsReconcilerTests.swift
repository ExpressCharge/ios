//
//  SettingsReconcilerTests.swift
//  DeviceSyncTests
//

import Foundation
import Testing

@testable import DeviceSync

@Suite("SettingsReconciler — LWW merge")
struct SettingsReconcilerTests {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_700_000_060)

    private func value(_ s: String, at: Date, by: String = "test") -> DeviceSettingValue {
        DeviceSettingValue(value: .string(s), updatedAt: at, updatedBy: by)
    }

    @Test func newerLocalWins() {
        let local = ["device.label": value("new", at: t1, by: "ios-app")]
        let remote = ["device.label": value("old", at: t0, by: "admin")]
        let merged = SettingsReconciler.merge(local: local, remote: remote)
        #expect(merged["device.label"]?.value == .string("new"))
        #expect(merged["device.label"]?.updatedBy == "ios-app")
    }

    @Test func olderLocalLosesToRemote() {
        let local = ["device.label": value("stale", at: t0, by: "ios-app")]
        let remote = ["device.label": value("fresh", at: t1, by: "admin")]
        let merged = SettingsReconciler.merge(local: local, remote: remote)
        #expect(merged["device.label"]?.value == .string("fresh"))
        #expect(merged["device.label"]?.updatedBy == "admin")
    }

    @Test func equalTimestampServerWins() {
        // Tie-break: server (remote) wins.
        let local = ["device.label": value("client", at: t0, by: "ios-app")]
        let remote = ["device.label": value("server", at: t0, by: "admin")]
        let merged = SettingsReconciler.merge(local: local, remote: remote)
        #expect(merged["device.label"]?.value == .string("server"))
    }

    @Test func keysOnlyOnLocalAreKept() {
        let local = ["new.key": value("v", at: t0)]
        let merged = SettingsReconciler.merge(local: local, remote: [:])
        #expect(merged["new.key"]?.value == .string("v"))
    }

    @Test func keysOnlyOnRemoteAreKept() {
        let remote = ["server.key": value("v", at: t0)]
        let merged = SettingsReconciler.merge(local: [:], remote: remote)
        #expect(merged["server.key"]?.value == .string("v"))
    }

    @Test func multiKeyMixedDirections() {
        let local = [
            "a": value("local-newer", at: t1),
            "b": value("local-older", at: t0),
            "only-local": value("c", at: t0),
        ]
        let remote = [
            "a": value("remote-older", at: t0),
            "b": value("remote-newer", at: t1),
            "only-remote": value("d", at: t0),
        ]
        let merged = SettingsReconciler.merge(local: local, remote: remote)
        #expect(merged["a"]?.value == .string("local-newer"))
        #expect(merged["b"]?.value == .string("remote-newer"))
        #expect(merged["only-local"]?.value == .string("c"))
        #expect(merged["only-remote"]?.value == .string("d"))
        #expect(merged.count == 4)
    }

    @Test func emptyOnBothSidesYieldsEmpty() {
        let merged = SettingsReconciler.merge(local: [:], remote: [:])
        #expect(merged.isEmpty)
    }
}
