//
//  LogDrain.swift
//  DeviceLogging
//
//  Pre/post-flight wrapper around `RingBufferLogStore` for the sync
//  envelope. `DeviceStateCoordinator.syncOnce()` calls
//  `pending(maxRecords:)` before building the request body and
//  `acknowledge(throughSeq:)` after the server returns 200.
//
//  Why a separate type rather than calling the store directly: the
//  drain tracks the in-flight cursor between the two calls so a
//  second concurrent `syncOnce()` (e.g. backgrounded sync racing with
//  a manual flush) doesn't double-drain the same range.
//

import Foundation

public actor LogDrain {

    public struct Drained: Sendable {
        public let records: [OTelLogRecord]
        public let cursor: UInt64?

        public var isEmpty: Bool { records.isEmpty }

        public init(records: [OTelLogRecord], cursor: UInt64?) {
            self.records = records
            self.cursor = cursor
        }
    }

    private let store: RingBufferLogStore
    /// Cursor of the last in-flight drain that hasn't been acknowledged
    /// yet. While non-nil, subsequent drains return empty so we don't
    /// race the first one's network round-trip.
    private var inFlightCursor: UInt64?

    public init(store: RingBufferLogStore) {
        self.store = store
    }

    /// Read up to `maxRecords` records newer than the last acked seq.
    /// Records are NOT removed; the caller acks after the network
    /// success.
    ///
    /// While a previous drain is in flight, returns empty — the
    /// coordinator just doesn't ship any logs that tick. The cursor is
    /// cleared on `acknowledge` (success) or `release` (any failure).
    public func pending(maxRecords: Int = 100) async -> Drained {
        if inFlightCursor != nil {
            return Drained(records: [], cursor: nil)
        }
        let snapshot = await store.snapshot(maxRecords: maxRecords)
        guard !snapshot.isEmpty else {
            return Drained(records: [], cursor: nil)
        }
        let cursor = snapshot.compactMap { Self.sequenceNumber(of: $0) }.max() ?? 0
        if cursor == 0 {
            return Drained(records: snapshot, cursor: nil)
        }
        inFlightCursor = cursor
        return Drained(records: snapshot, cursor: cursor)
    }

    /// Mark every record at or below `cursor` as acked. Triggers
    /// compaction in the underlying store. Called after the server's
    /// 200 response.
    public func acknowledge(throughSeq cursor: UInt64) async {
        await store.ack(throughSeq: cursor)
        inFlightCursor = nil
    }

    /// Discard the in-flight cursor without acking. Called when the
    /// sync request fails (any reason) so the next `pending()` re-drains
    /// the same records.
    public func release() {
        inFlightCursor = nil
    }

    /// Wipe everything. Token-revocation cleanup path.
    public func purge() async {
        await store.purge()
        inFlightCursor = nil
    }

    /// Newest-first read for the diagnostics sheet.
    public func recent(limit: Int) async -> [OTelLogRecord] {
        await store.recent(limit: limit)
    }

    private static func sequenceNumber(of record: OTelLogRecord) -> UInt64? {
        guard case .string(let s) = record.attributes["expresscharge.seq"] else { return nil }
        return UInt64(s)
    }
}
