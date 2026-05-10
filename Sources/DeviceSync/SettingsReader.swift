//
//  SettingsReader.swift
//  DeviceSync
//
//  SwiftUI-observable reader over `SettingsStore`'s snapshot. Closes the
//  pre-existing gap where `SettingsStore` (an `actor`) wasn't directly
//  readable from SwiftUI views — view-models reached into UserDefaults
//  instead. With this reader, views can read AND write through the same
//  observable surface as feature flags.
//
//  Updated by `DeviceStateCoordinator.applyEnvelope(_:)` whenever a new
//  envelope lands (so server-merged settings show up immediately).
//

import Foundation
import Models
import Observation

@MainActor
@Observable
public final class SettingsReader {

    /// Latest known per-device settings snapshot.
    public private(set) var snapshot: [String: DeviceSettingValue]

    @ObservationIgnored
    private let store: SettingsStore

    public init(
        store: SettingsStore,
        snapshot: [String: DeviceSettingValue] = [:]
    ) {
        self.store = store
        self.snapshot = snapshot
    }

    /// Replace the in-memory snapshot. Called by the coordinator after
    /// `applyEnvelope`.
    public func update(_ snapshot: [String: DeviceSettingValue]) {
        self.snapshot = snapshot
    }

    /// Write-through wrapper that calls `SettingsStore.setLocal` and
    /// optimistically reflects the change in the in-memory snapshot so
    /// SwiftUI views see the new value before the next sync tick.
    public func setLocal(
        key: String,
        value: AnyCodableJSON,
        updatedBy: String = "ios-app"
    ) async throws {
        let now = Date()
        try await store.setLocal(
            key: key,
            value: value,
            updatedAt: now,
            updatedBy: updatedBy
        )
        snapshot[key] = DeviceSettingValue(
            value: value,
            updatedAt: now,
            updatedBy: updatedBy
        )
    }

    // MARK: - Typed reads (mirror FeatureFlagReader)

    public func bool(_ key: String, default fallback: Bool) -> Bool {
        guard let entry = snapshot[key] else { return fallback }
        if case .bool(let b) = entry.value { return b }
        return fallback
    }

    public func string(_ key: String, default fallback: String) -> String {
        guard let entry = snapshot[key] else { return fallback }
        if case .string(let s) = entry.value { return s }
        return fallback
    }

    public func int(_ key: String, default fallback: Int64) -> Int64 {
        guard let entry = snapshot[key] else { return fallback }
        switch entry.value {
        case .int(let i): return i
        case .double(let d): return Int64(d)
        default: return fallback
        }
    }

    public func double(_ key: String, default fallback: Double) -> Double {
        guard let entry = snapshot[key] else { return fallback }
        switch entry.value {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return fallback
        }
    }
}
