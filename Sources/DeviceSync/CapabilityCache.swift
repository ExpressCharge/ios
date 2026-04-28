//
//  CapabilityCache.swift
//  DeviceSync
//
//  Tiny `UserDefaults`-backed persistent cache for the device's last
//  observed capability set. Read on cold launch so the SwiftUI shell can
//  render with known-good capabilities BEFORE the first
//  `GET /api/devices/me/state` resolves — closes the P1-9 "tab they no
//  longer have access to" flash window from the UX research.
//
//  Pure Foundation; no UIKit / SwiftUI imports — keeps this module's
//  banned-imports invariant intact.
//

import Foundation
import Models

/// Persistent cache of the most recently observed capability set. Treat
/// the cache as advisory — the authoritative source is the live
/// `DeviceState.capabilities` returned from the server.
public final class CapabilityCache: @unchecked Sendable {

    /// `UserDefaults` key. Suffix is versioned so a future schema change
    /// can be rolled out by bumping the version without colliding.
    public static let storageKey = "DeviceSync.cachedCapabilities"

    // `UserDefaults` is not `Sendable` in Swift 6 even though it's
    // documented as thread-safe. Mark this class `@unchecked Sendable`
    // — the only mutation we do is via `set(_:forKey:)` which is
    // thread-safe on `UserDefaults`.
    private let defaults: UserDefaults

    /// - Parameter defaults: Defaults to `.standard`. Tests pass an
    ///   isolated `UserDefaults(suiteName:)` so they don't pollute the
    ///   shared store.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Persist the current capability set. Writes the raw-string array
    /// representation (`UserDefaults` doesn't support `Set<Enum>`
    /// natively).
    public func write(_ caps: Set<DeviceCapability>) {
        let raw = caps.map(\.rawValue).sorted()
        defaults.set(raw, forKey: Self.storageKey)
    }

    /// Read the last persisted capability set. Returns `nil` when the
    /// key is absent (fresh install, never synced) — callers fall back
    /// to a sensible default like `[.scanner, .user]`.
    public func read() -> Set<DeviceCapability>? {
        guard let raw = defaults.array(forKey: Self.storageKey) as? [String] else {
            return nil
        }
        var out: Set<DeviceCapability> = []
        for entry in raw {
            if let cap = DeviceCapability(rawValue: entry) {
                out.insert(cap)
            }
        }
        // An empty cached array is legal-but-useless — surface it as a
        // hit so callers can distinguish "never written" (nil) from
        // "explicitly empty" (Set()).
        return out
    }

    /// Erase the cache entirely. Called on sign-out so the next user's
    /// first cold launch doesn't render with stale capabilities.
    public func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
