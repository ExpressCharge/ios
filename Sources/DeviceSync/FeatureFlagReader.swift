//
//  FeatureFlagReader.swift
//  DeviceSync
//
//  SwiftUI-observable reader over the `DeviceState.flags` map. Exposes
//  typed string-keyed reads with safe defaults so call-sites can pull a
//  flag without unwrapping `AnyCodableJSON`.
//
//  Updated by `DeviceStateCoordinator.applyEnvelope(_:)` whenever a new
//  envelope lands (cold launch, 60s sync tick, SSE-driven refresh).
//
//  Snapshot is the default-omit map — only flags whose effective value
//  differs from the registry default are present, so a missing key
//  intentionally returns the caller's `default:` argument.
//

import Foundation
import Models
import Observation

@MainActor
@Observable
public final class FeatureFlagReader {

    /// Latest snapshot received from the server. Read-only to outside
    /// callers; mutated through `update(_:)`.
    public private(set) var snapshot: [String: DeviceSettingValue]

    public init(snapshot: [String: DeviceSettingValue] = [:]) {
        self.snapshot = snapshot
    }

    /// Replace the snapshot in one shot. Triggered by the coordinator
    /// after an envelope apply.
    public func update(_ snapshot: [String: DeviceSettingValue]) {
        self.snapshot = snapshot
    }

    // MARK: - Typed reads
    //
    // Each typed read defensively unwraps the heterogeneous JSON value:
    // a flag whose registry type is `Bool` should never decode as a
    // string, but a misbehaving server (or a registry change rolled out
    // ahead of the client) shouldn't crash the app — return the default.

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
