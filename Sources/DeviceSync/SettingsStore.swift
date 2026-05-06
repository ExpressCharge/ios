//
//  SettingsStore.swift
//  DeviceSync
//
//  Actor wrapping the on-disk per-device settings store. Persists a JSON
//  blob at `~/Library/Application Support/ExpresScan/settings.json`
//  (overridable for tests via `directoryURL`).
//
//  File format (matches the in-memory shape):
//
//      {
//        "values": {
//          "device.label": {
//            "value": "Vlad's iPhone",
//            "updatedAt": "2026-04-27T...",
//            "updatedBy": "ios-app"
//          },
//          ...
//        },
//        "dirty": ["device.label"]
//      }
//
//  Writes are atomic: encode → write to a tempfile in the same directory
//  → `replaceItemAt` to swap. This way a partial write never leaves the
//  store corrupted.
//

import Foundation

public actor SettingsStore {

    // MARK: - Persisted blob

    /// On-disk shape. Internal only; callers see `(values, dirty)`.
    private struct Blob: Codable {
        var values: [String: DeviceSettingValue]
        var dirty: [String]
    }

    // MARK: - State

    /// In-memory authoritative state. Synced to disk on every mutation.
    private var values: [String: DeviceSettingValue] = [:]
    private var dirtyKeys: Set<String> = []
    private var loaded: Bool = false

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: - Init

    /// Designated initialiser.
    ///
    /// - Parameter directoryURL: Defaults to
    ///   `~/Library/Application Support/ExpressCharge/`. Tests pass a
    ///   per-test temp directory.
    public init(directoryURL: URL? = nil) throws {
        let dir: URL
        if let directoryURL {
            dir = directoryURL
        } else {
            // iOS 16+ / macOS 13+ — `URL.applicationSupportDirectory`.
            let base = URL.applicationSupportDirectory
            dir = base.appendingPathComponent("ExpressCharge", isDirectory: true)
        }
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        self.fileURL = dir.appendingPathComponent("settings.json", isDirectory: false)

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    // MARK: - Public API

    /// Load the on-disk state into memory. Idempotent — subsequent calls
    /// are no-ops once loaded. Missing file → empty store.
    public func load() throws {
        if loaded { return }
        loaded = true

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            values = [:]
            dirtyKeys = []
            return
        }

        let data = try Data(contentsOf: fileURL)
        if data.isEmpty {
            values = [:]
            dirtyKeys = []
            return
        }
        let blob = try decoder.decode(Blob.self, from: data)
        values = blob.values
        dirtyKeys = Set(blob.dirty)
    }

    /// Read-only snapshot of all values. Implicitly loads the store.
    public func allValues() throws -> [String: DeviceSettingValue] {
        try load()
        return values
    }

    /// The set of keys with local changes that have not yet been synced
    /// to the server.
    public func dirty() throws -> Set<String> {
        try load()
        return dirtyKeys
    }

    /// Pending settings ready to be sent in a `SyncRequest`. ISO-8601
    /// stamps; ordering by key is stable for snapshot-friendly tests.
    public func pendingSettingsForSync() throws -> [SyncRequest.PendingSetting] {
        try load()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return
            dirtyKeys
            .sorted()
            .compactMap { key -> SyncRequest.PendingSetting? in
                guard let v = values[key] else { return nil }
                return SyncRequest.PendingSetting(
                    key: key,
                    value: v.value,
                    updatedAt: formatter.string(from: v.updatedAt)
                )
            }
    }

    /// Set a value locally and mark its key as dirty.
    public func setLocal(
        key: String,
        value: AnyCodableJSON,
        updatedAt: Date = Date(),
        updatedBy: String = "ios-app"
    ) throws {
        try load()
        values[key] = DeviceSettingValue(
            value: value,
            updatedAt: updatedAt,
            updatedBy: updatedBy
        )
        dirtyKeys.insert(key)
        try persist()
    }

    /// Apply a server-merged map, overwriting all local state and
    /// clearing the dirty set. Called after a successful
    /// `POST /me/state/sync` response.
    public func applyMerged(_ merged: [String: DeviceSettingValue]) throws {
        try load()
        values = merged
        dirtyKeys = []
        try persist()
    }

    // MARK: - Private

    private func persist() throws {
        let blob = Blob(values: values, dirty: Array(dirtyKeys).sorted())
        let data = try encoder.encode(blob)
        try writeAtomically(data: data, to: fileURL)
    }

    /// Write `data` to `url` atomically — encode to a sibling tempfile,
    /// then swap with `replaceItemAt`.
    private func writeAtomically(data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        let tmp = dir.appendingPathComponent(
            ".\(url.lastPathComponent).tmp-\(UUID().uuidString)",
            isDirectory: false
        )
        try data.write(to: tmp, options: [.atomic])
        // `replaceItemAt` handles the destination already existing.
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }
}
