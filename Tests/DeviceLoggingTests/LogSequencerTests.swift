//
//  LogSequencerTests.swift
//  DeviceLoggingTests
//
//  Pins monotonicity + persistence semantics. The server's `device_logs`
//  PK is `(device_id, seq)` so any non-monotonic allocation would make
//  inserts collide and silently drop new records.
//

import Foundation
import Testing

@testable import DeviceLogging

@Suite("LogSequencer")
struct LogSequencerTests {

    @Test func allocatesStrictlyMonotonic() {
        let defaults = makeDefaults()
        let s = LogSequencer(defaults: defaults)
        var values: [UInt64] = []
        for _ in 0..<1_000 { values.append(s.next()) }
        for i in 1..<values.count {
            #expect(values[i] > values[i - 1])
        }
    }

    @Test func persistsAcrossInstances() {
        let defaults = makeDefaults()
        let first = LogSequencer(defaults: defaults)
        for _ in 0..<5 { _ = first.next() }
        let highestFirst = first.current

        let second = LogSequencer(defaults: defaults)
        let next = second.next()
        #expect(next > highestFirst)
    }

    @Test func resetMovesFloor() {
        let defaults = makeDefaults()
        let s = LogSequencer(defaults: defaults)
        s.reset(to: 1_000_000)
        #expect(s.current == 1_000_000)
        #expect(s.next() == 1_000_001)
    }

    @Test func concurrentNextCallsAreUnique() async {
        let defaults = makeDefaults()
        let s = LogSequencer(defaults: defaults)
        let count = 1_000
        let allocated = await withTaskGroup(of: UInt64.self, returning: Set<UInt64>.self) {
            group in
            for _ in 0..<count {
                group.addTask { s.next() }
            }
            var set: Set<UInt64> = []
            for await v in group { set.insert(v) }
            return set
        }
        #expect(allocated.count == count)
    }

    private func makeDefaults() -> UserDefaults {
        // Ephemeral suite — `removeSuite` keeps tests independent.
        let name = "DeviceLoggingTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
}
