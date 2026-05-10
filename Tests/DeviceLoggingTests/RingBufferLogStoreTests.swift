//
//  RingBufferLogStoreTests.swift
//  DeviceLoggingTests
//
//  Append/snapshot/ack cycle, partial-line recovery on relaunch, and
//  the readRecent ordering that the DiagnosticsSheet depends on.
//

import Foundation
import Testing

@testable import DeviceLogging

@Suite("RingBufferLogStore")
struct RingBufferLogStoreTests {

    @Test func appendThenSnapshotReturnsRecordsInSeqOrder() async throws {
        let store = try makeStore()
        for i in 1...5 {
            await store.append(makeRecord(seq: UInt64(i), body: "msg\(i)"))
        }
        let snapshot = await store.snapshot(maxRecords: 100)
        #expect(snapshot.count == 5)
        #expect(snapshot.first?.body == "msg1")
        #expect(snapshot.last?.body == "msg5")
    }

    @Test func ackDropsRecordsAtOrBelowCursor() async throws {
        let store = try makeStore()
        for i in 1...10 {
            await store.append(makeRecord(seq: UInt64(i), body: "msg\(i)"))
        }
        await store.ack(throughSeq: 5)
        let remaining = await store.snapshot(maxRecords: 100)
        let bodies = remaining.map(\.body)
        #expect(bodies == ["msg6", "msg7", "msg8", "msg9", "msg10"])
    }

    @Test func recentReturnsNewestFirst() async throws {
        let store = try makeStore()
        for i in 1...10 {
            await store.append(makeRecord(seq: UInt64(i), body: "msg\(i)"))
        }
        let recent = await store.recent(limit: 3)
        #expect(recent.count == 3)
        #expect(recent.first?.body == "msg10")
        #expect(recent.last?.body == "msg8")
    }

    @Test func purgeWipesEverything() async throws {
        let store = try makeStore()
        await store.append(makeRecord(seq: 1, body: "x"))
        await store.purge()
        let snapshot = await store.snapshot(maxRecords: 100)
        #expect(snapshot.isEmpty)
        #expect(await store.lastAckedSeq() == 0)
    }

    @Test func tornLineSurvivedOnRecount() async throws {
        let directory = try makeDirectory()
        let store = try RingBufferLogStore(directory: directory)
        await store.append(makeRecord(seq: 1, body: "good"))

        // Simulate a crash mid-write — append a half-record without a
        // trailing newline.
        let logURL = directory.appendingPathComponent("log.jsonl")
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"timestamp\":42,\"observed".utf8))
        try handle.close()

        // Re-open the store as if the process restarted.
        let reopened = try RingBufferLogStore(directory: directory)
        let snapshot = await reopened.snapshot(maxRecords: 100)
        #expect(snapshot.count == 1)
        #expect(snapshot.first?.body == "good")
    }

    @Test func highestSeqOnDiskIsHighestPersistedSeq() async throws {
        let store = try makeStore()
        await store.append(makeRecord(seq: 7, body: "a"))
        await store.append(makeRecord(seq: 99, body: "b"))
        await store.append(makeRecord(seq: 12, body: "c"))
        let highest = await store.highestSeqOnDisk()
        #expect(highest == 99)
    }

    // MARK: - Fixture

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceLoggingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeStore() throws -> RingBufferLogStore {
        let dir = try makeDirectory()
        return try RingBufferLogStore(directory: dir)
    }

    private func makeRecord(seq: UInt64, body: String) -> OTelLogRecord {
        OTelLogRecord(
            timestamp: 1,
            observedTimestamp: 1,
            severityText: "INFO",
            severityNumber: 9,
            body: body,
            attributes: ["expresscharge.seq": .string("\(seq)")],
            resource: [:]
        )
    }
}
