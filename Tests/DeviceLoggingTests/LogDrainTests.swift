//
//  LogDrainTests.swift
//  DeviceLoggingTests
//
//  Drain semantics: pending() returns records, acknowledge() advances
//  the cursor, release() retries the same range, and concurrent
//  pending() calls don't double-drain.
//

import Foundation
import Testing

@testable import DeviceLogging

@Suite("LogDrain")
struct LogDrainTests {

    @Test func pendingThenAcknowledgeAdvancesCursor() async throws {
        let store = try makeStore()
        for i in 1...3 {
            await store.append(record(seq: UInt64(i)))
        }
        let drain = LogDrain(store: store)
        let drained = await drain.pending(maxRecords: 100)
        #expect(drained.records.count == 3)
        #expect(drained.cursor == 3)

        await drain.acknowledge(throughSeq: 3)
        let next = await drain.pending(maxRecords: 100)
        #expect(next.records.isEmpty)
    }

    @Test func releaseRetriesSameRange() async throws {
        let store = try makeStore()
        for i in 1...3 { await store.append(record(seq: UInt64(i))) }
        let drain = LogDrain(store: store)
        let first = await drain.pending(maxRecords: 100)
        #expect(first.cursor == 3)
        await drain.release()
        let second = await drain.pending(maxRecords: 100)
        #expect(second.cursor == 3)
        #expect(second.records.count == 3)
    }

    @Test func concurrentPendingDoesNotDoubleDrainInFlight() async throws {
        let store = try makeStore()
        for i in 1...5 { await store.append(record(seq: UInt64(i))) }
        let drain = LogDrain(store: store)
        let first = await drain.pending(maxRecords: 100)
        // Second call while first is in flight (no ack yet) returns empty.
        let second = await drain.pending(maxRecords: 100)
        #expect(first.records.count == 5)
        #expect(second.records.isEmpty)
        #expect(second.cursor == nil)
    }

    @Test func purgeWipesBufferAndCursor() async throws {
        let store = try makeStore()
        await store.append(record(seq: 1))
        let drain = LogDrain(store: store)
        _ = await drain.pending(maxRecords: 100)
        await drain.purge()
        let next = await drain.pending(maxRecords: 100)
        #expect(next.records.isEmpty)
    }

    // MARK: - Fixture

    private func makeStore() throws -> RingBufferLogStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceLoggingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try RingBufferLogStore(directory: dir)
    }

    private func record(seq: UInt64) -> OTelLogRecord {
        OTelLogRecord(
            timestamp: 1,
            observedTimestamp: 1,
            severityText: "INFO",
            severityNumber: 9,
            body: "msg\(seq)",
            attributes: ["expresscharge.seq": .string("\(seq)")],
            resource: [:]
        )
    }
}
