//
//  SettingsStoreTests.swift
//  DeviceSyncTests
//

import Foundation
import Testing

@testable import DeviceSync

@Suite("SettingsStore — actor + on-disk persistence")
struct SettingsStoreTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ExpresScan-SettingsStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func loadEmptyStore() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SettingsStore(directoryURL: dir)
        try await store.load()
        let values = try await store.allValues()
        let dirty = try await store.dirty()
        #expect(values.isEmpty)
        #expect(dirty.isEmpty)
    }

    @Test func setLocalFlipsDirty() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SettingsStore(directoryURL: dir)
        try await store.setLocal(
            key: "device.label",
            value: .string("Vlad's iPhone")
        )
        let dirty = try await store.dirty()
        let values = try await store.allValues()
        #expect(dirty == ["device.label"])
        #expect(values["device.label"]?.value == .string("Vlad's iPhone"))
    }

    @Test func applyMergedClearsDirty() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SettingsStore(directoryURL: dir)
        try await store.setLocal(key: "device.label", value: .string("v"))
        #expect(try await store.dirty() == ["device.label"])

        let merged: [String: DeviceSettingValue] = [
            "device.label": DeviceSettingValue(
                value: .string("server-merged"),
                updatedAt: Date(),
                updatedBy: "admin"
            )
        ]
        try await store.applyMerged(merged)
        #expect(try await store.dirty().isEmpty)
        let values = try await store.allValues()
        #expect(values["device.label"]?.value == .string("server-merged"))
        #expect(values["device.label"]?.updatedBy == "admin")
    }

    @Test func persistsAcrossReload() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // First store: write some state.
        do {
            let store = try SettingsStore(directoryURL: dir)
            try await store.setLocal(key: "device.label", value: .string("hello"))
            try await store.setLocal(key: "notifications.scanRequest", value: .bool(true))
        }

        // Second store at the same directory: should load both keys
        // and the dirty set.
        let store2 = try SettingsStore(directoryURL: dir)
        try await store2.load()
        let values = try await store2.allValues()
        let dirty = try await store2.dirty()
        #expect(values.count == 2)
        #expect(values["device.label"]?.value == .string("hello"))
        #expect(values["notifications.scanRequest"]?.value == .bool(true))
        #expect(dirty == ["device.label", "notifications.scanRequest"])
    }

    @Test func pendingSettingsForSyncReturnsOnlyDirty() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SettingsStore(directoryURL: dir)
        // Simulate a server-merged baseline (clean).
        try await store.applyMerged([
            "device.label": DeviceSettingValue(
                value: .string("clean"),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedBy: "admin"
            )
        ])
        // Make a local edit on a different key.
        try await store.setLocal(
            key: "notifications.scanRequest",
            value: .bool(false)
        )
        let pending = try await store.pendingSettingsForSync()
        #expect(pending.count == 1)
        #expect(pending.first?.key == "notifications.scanRequest")
        #expect(pending.first?.value == .bool(false))
    }
}
