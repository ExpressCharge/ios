//
//  LogSequencer.swift
//  DeviceLogging
//
//  Hands out per-device monotonic UInt64 sequence numbers, persisted in
//  `UserDefaults` so they survive process restart. The server uses
//  `(device_id, seq)` as the `device_logs` PK to dedupe replays —
//  monotonicity is load-bearing.
//
//  This is intentionally NOT an actor: the `swift-log` `LogHandler.log`
//  method is non-async, and we need a synchronous `next()` so call
//  sites stay fire-and-forget. Concurrency is guarded by
//  `OSAllocatedUnfairLock`, which is contention-cheap and Swift-6
//  strict-concurrency clean.
//

import Foundation
import os

/// Monotonic UInt64 allocator. Thread-safe; one instance per process.
/// `@unchecked Sendable` because `UserDefaults` itself isn't statically
/// `Sendable` but its `set(_:forKey:)` is documented thread-safe (see
/// the Foundation header). Actual mutation is serialized via the
/// `OSAllocatedUnfairLock` around `state`.
public final class LogSequencer: @unchecked Sendable {

    private static let userDefaultsKey = "com.example.expresscharge.ios.DeviceLogging.lastSeq"

    private let state: OSAllocatedUnfairLock<UInt64>
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.object(forKey: Self.userDefaultsKey) as? NSNumber
        let initial: UInt64 = stored?.uint64Value ?? 0
        self.state = OSAllocatedUnfairLock(initialState: initial)
    }

    /// Allocate the next seq. Always strictly greater than every
    /// previously-returned value for this process AND every seq
    /// previously persisted across app launches.
    public func next() -> UInt64 {
        state.withLock { current in
            current &+= 1
            defaults.set(NSNumber(value: current), forKey: Self.userDefaultsKey)
            return current
        }
    }

    /// Highest seq this allocator has handed out in the current process.
    public var current: UInt64 {
        state.withLock { $0 }
    }

    /// Force the counter to a specific floor. Only the boot-time sink
    /// reconciliation calls this — never call it after sequence numbers
    /// have started flowing into the ring buffer.
    public func reset(to seq: UInt64) {
        state.withLock { current in
            current = seq
            defaults.set(NSNumber(value: current), forKey: Self.userDefaultsKey)
        }
    }
}
