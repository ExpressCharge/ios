//
//  RingBufferLogStore.swift
//  DeviceLogging
//
//  JSONL-on-disk persistence for the swift-log façade. Append-only on
//  the hot path; bounded by a size-and-count cap with compact-on-overflow.
//
//  - O(1) append via `FileHandle.write(contentsOf:)`.
//  - Crash-safe: a torn line at the tail (process killed mid-write) is
//    skipped on next read; everything before is intact.
//  - No SQLite dependency; this is ~250 lines of Swift.
//
//  Eviction: when an append crosses the size or count cap, we read all
//  lines, drop the oldest down to a target count, atomically rename the
//  rewritten file in place, and reopen the handle. Sequence numbers are
//  NOT renumbered — we just drop entries below the new floor.
//
//  Location: `Application Support/DeviceLogging/log.jsonl` plus a
//  sidecar `log.cursor` holding the last-acked seq (string-encoded
//  UInt64). Excluded from iCloud backup at first write.
//

import Foundation
import os

private let storeLog = Logger(subsystem: "com.example.expresscharge.ios", category: "DeviceLogStore")

/// Bounded JSONL ring buffer of `OTelLogRecord`s. Actor-isolated so
/// fire-and-forget appends from many call sites serialize through
/// one writer.
public actor RingBufferLogStore {

    /// Target retained-record count after compaction. Leaves headroom
    /// below `maxRecords` so compaction amortizes.
    public static let compactTargetRecords: Int = 8_000
    /// Hard cap on retained records before compaction triggers.
    public static let maxRecords: Int = 10_000
    /// Hard cap on file size before compaction triggers.
    public static let maxBytes: Int = 5 * 1024 * 1024

    private let directory: URL
    private let logURL: URL
    private let cursorURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var recordCount: Int = 0
    private var byteCount: Int = 0
    private var droppedCount: UInt64 = 0

    public init(directory: URL) throws {
        self.directory = directory
        self.logURL = directory.appendingPathComponent("log.jsonl")
        self.cursorURL = directory.appendingPathComponent("log.cursor")
        self.encoder = Self.defaultEncoder()
        self.decoder = Self.defaultDecoder()
        try Self.ensureDirectory(directory)
        // Initial counts come from the file synchronously — actor-isolated
        // methods can't be called from `init` so we use the static helper.
        let counts = try Self.recountFromDisk(at: logURL)
        self.recordCount = counts.records
        self.byteCount = counts.bytes
    }

    // MARK: - Convenience constructor

    /// Default-location constructor — `Application Support/DeviceLogging/`.
    /// Throws if the directory can't be created.
    public static func defaultLocation() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support.appendingPathComponent("DeviceLogging", isDirectory: true)
    }

    // MARK: - Ingestion

    /// Append one record. Triggers compaction if either cap is exceeded.
    public func append(_ record: OTelLogRecord) {
        do {
            let line = try encoder.encode(record) + Data([0x0A])
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            recordCount &+= 1
            byteCount &+= line.count
            if recordCount > Self.maxRecords || byteCount > Self.maxBytes {
                try compact()
            }
        } catch {
            droppedCount &+= 1
            storeLog.error(
                "RingBufferLogStore.append: \(String(describing: error), privacy: .public)"
            )
        }
    }

    // MARK: - Drain (sync hand-off)

    /// Records with `seq > lastAcked`, oldest-first, up to `maxRecords`.
    /// Non-destructive — the caller acks after the network round-trip
    /// succeeds. Skips torn lines silently.
    public func snapshot(maxRecords: Int) -> [OTelLogRecord] {
        guard FileManager.default.fileExists(atPath: logURL.path) else { return [] }
        guard let data = try? Data(contentsOf: logURL), !data.isEmpty else { return [] }

        let acked = lastAckedSeq()
        var out: [OTelLogRecord] = []
        out.reserveCapacity(min(maxRecords, 256))
        var skipped = 0
        for slice in lines(in: data) {
            if let record = try? decoder.decode(OTelLogRecord.self, from: slice) {
                if let seq = sequenceNumber(of: record), seq > acked {
                    out.append(record)
                    if out.count >= maxRecords { break }
                }
            } else {
                skipped &+= 1
            }
        }
        if skipped > 0 {
            storeLog.warning(
                "RingBufferLogStore.snapshot: skipped \(skipped, privacy: .public) torn line(s)"
            )
        }
        return out
    }

    /// Mark every record through `seq` as acked. Triggers compaction so
    /// the on-disk file shrinks.
    public func ack(throughSeq seq: UInt64) {
        do {
            try Data("\(seq)\n".utf8).write(to: cursorURL, options: .atomic)
            try compact(keepingSeqsAbove: seq)
        } catch {
            storeLog.error(
                "RingBufferLogStore.ack: \(String(describing: error), privacy: .public)"
            )
        }
    }

    // MARK: - Read (DiagnosticsSheet)

    /// Newest-first up to `limit` records.
    public func recent(limit: Int) -> [OTelLogRecord] {
        guard FileManager.default.fileExists(atPath: logURL.path) else { return [] }
        guard let data = try? Data(contentsOf: logURL), !data.isEmpty else { return [] }
        let bounded = min(max(limit, 1), 200)

        var all: [OTelLogRecord] = []
        all.reserveCapacity(256)
        for slice in lines(in: data) {
            if let record = try? decoder.decode(OTelLogRecord.self, from: slice) {
                all.append(record)
            }
        }
        all.sort { (a, b) in
            (sequenceNumber(of: a) ?? 0) > (sequenceNumber(of: b) ?? 0)
        }
        if all.count > bounded { all.removeSubrange(bounded..<all.count) }
        return all
    }

    // MARK: - Lifecycle

    /// Wipe everything. Used by token-revocation cleanup — logs are
    /// owner-scoped PII.
    public func purge() {
        if FileManager.default.fileExists(atPath: logURL.path) {
            try? FileManager.default.removeItem(at: logURL)
        }
        if FileManager.default.fileExists(atPath: cursorURL.path) {
            try? FileManager.default.removeItem(at: cursorURL)
        }
        recordCount = 0
        byteCount = 0
    }

    /// Highest seq present on disk, ignoring acked records. Used by
    /// `LoggingBootstrap` to reconcile the in-memory `LogSequencer` so
    /// post-restart allocations don't overlap.
    public func highestSeqOnDisk() -> UInt64 {
        guard FileManager.default.fileExists(atPath: logURL.path) else { return 0 }
        guard let data = try? Data(contentsOf: logURL), !data.isEmpty else { return 0 }
        var highest: UInt64 = 0
        for slice in lines(in: data) {
            if let record = try? decoder.decode(OTelLogRecord.self, from: slice) {
                if let seq = sequenceNumber(of: record), seq > highest { highest = seq }
            }
        }
        return highest
    }

    /// Last-acked seq, or 0 if none.
    public func lastAckedSeq() -> UInt64 {
        guard FileManager.default.fileExists(atPath: cursorURL.path) else { return 0 }
        guard let data = try? Data(contentsOf: cursorURL) else { return 0 }
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return UInt64(text) ?? 0
    }

    /// Count of failed appends since process start. Surfaced in
    /// diagnostics; reset on app launch.
    public func droppedSinceLaunch() -> UInt64 {
        droppedCount
    }

    // MARK: - Internals

    /// Pull `attributes["expresscharge.seq"]` as a UInt64, since the wire
    /// stores it as a string. Records missing the seq attribute (which
    /// shouldn't happen if `RingBufferJSONLogHandler` is the only
    /// writer) are treated as seq 0 by callers.
    private func sequenceNumber(of record: OTelLogRecord) -> UInt64? {
        guard case .string(let s) = record.attributes["expresscharge.seq"] else { return nil }
        return UInt64(s)
    }

    /// Keep the newest `compactTargetRecords` entries — or, when called
    /// by `ack`, every record with `seq > floorSeq`.
    private func compact(keepingSeqsAbove floorSeq: UInt64? = nil) throws {
        guard FileManager.default.fileExists(atPath: logURL.path) else { return }
        let data = try Data(contentsOf: logURL)
        var records: [OTelLogRecord] = []
        for slice in lines(in: data) {
            if let record = try? decoder.decode(OTelLogRecord.self, from: slice) {
                records.append(record)
            }
        }
        records.sort { (a, b) in
            (sequenceNumber(of: a) ?? 0) < (sequenceNumber(of: b) ?? 0)
        }
        if let floor = floorSeq {
            records.removeAll { (sequenceNumber(of: $0) ?? 0) <= floor }
        } else if records.count > Self.compactTargetRecords {
            records.removeFirst(records.count - Self.compactTargetRecords)
        }

        let tmpURL = directory.appendingPathComponent("log.jsonl.tmp")
        var rewritten = Data()
        rewritten.reserveCapacity(records.count * 256)
        for record in records {
            let line = try encoder.encode(record)
            rewritten.append(line)
            rewritten.append(0x0A)
        }
        try rewritten.write(to: tmpURL, options: .atomic)
        _ = try FileManager.default.replaceItemAt(logURL, withItemAt: tmpURL)
        recordCount = records.count
        byteCount = rewritten.count
    }

    private static func recountFromDisk(at url: URL) throws -> (records: Int, bytes: Int) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return (0, 0)
        }
        let data = try Data(contentsOf: url)
        var count = 0
        for byte in data where byte == 0x0A { count &+= 1 }
        return (count, data.count)
    }

    /// Splits `data` on `\n` boundaries, dropping empty slices. Used by
    /// every read path so they all agree on what counts as a record.
    private func lines(in data: Data) -> [Data] {
        var out: [Data] = []
        var start = data.startIndex
        for i in data.indices where data[i] == 0x0A {
            if i > start {
                out.append(data.subdata(in: start..<i))
            }
            start = data.index(after: i)
        }
        if start < data.endIndex {
            out.append(data.subdata(in: start..<data.endIndex))
        }
        return out
    }

    private static func ensureDirectory(_ url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = url
            try? mutableURL.setResourceValues(values)
        }
    }

    public static func defaultEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        // OTel `timestamp` / `observed_timestamp` are nanos-since-epoch
        // ints — no date-encoding strategy needed; the wire shape is
        // already integer.
        return e
    }

    public static func defaultDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}
