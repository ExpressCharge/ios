//
//  RingBufferJSONLogHandler.swift
//  DeviceLogging
//
//  `swift-log` `LogHandler` that turns each log call into an
//  `OTelLogRecord`, scrubs PII, and appends to the durable
//  `RingBufferLogStore`. The other half of the multiplex
//  (`OSLogHandler`) emits to Apple's `os.Logger` for Console.app.
//
//  The handler is `Sendable`; per swift-log's contract,
//  `LogHandler` instances are `struct`s with mutable metadata, so
//  copies are produced per-`Logger`. The store reference + sequencer
//  + resource block are shared by reference (the actor handles
//  serialization).
//

import Foundation
import Logging
import Models

public struct RingBufferJSONLogHandler: LogHandler {

    public var metadata: Logger.Metadata = [:]
    public var logLevel: Logger.Level = .info
    public var metadataProvider: Logger.MetadataProvider?

    private let label: String
    private let store: RingBufferLogStore
    private let sequencer: LogSequencer
    private let resource: [String: String]
    private let clock: @Sendable () -> Date

    public init(
        label: String,
        store: RingBufferLogStore,
        sequencer: LogSequencer,
        resource: [String: String],
        metadataProvider: Logger.MetadataProvider? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.label = label
        self.store = store
        self.sequencer = sequencer
        self.resource = resource
        self.metadataProvider = metadataProvider
        self.clock = clock
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        // Build the record on the calling thread so timestamps and seq
        // allocation reflect the actual call-site moment, not the
        // actor-task hop. The append itself is async fire-and-forget.
        let now = clock()
        let nanos = Int64(now.timeIntervalSince1970 * 1_000_000_000)
        let seq = sequencer.next()

        var attributes: [String: AnyCodableJSON] = [:]
        attributes["expresscharge.seq"] = .string("\(seq)")
        attributes["category"] = .string(label)
        attributes["code.function"] = .string(function)
        attributes["code.filepath"] = .string(file)
        attributes["code.lineno"] = .int(Int64(line))

        var merged = self.metadata
        if let providerMetadata = metadataProvider?.get() {
            merged.merge(providerMetadata) { _, new in new }
        }
        if let callerMetadata = metadata {
            merged.merge(callerMetadata) { _, new in new }
        }
        for (key, value) in merged {
            attributes[key] = Self.convert(value)
        }

        var record = OTelLogRecord(
            timestamp: nanos,
            observedTimestamp: nanos,
            severityText: OTelSeverity.text(for: Self.toLogLevel(level)),
            severityNumber: OTelSeverity.number(for: Self.toLogLevel(level)),
            body: "\(message)",
            attributes: attributes,
            resource: resource
        )
        LogScrubber.scrub(&record)

        // Fire-and-forget — the actor serializes appends; back-pressure
        // is bounded by the actor's mailbox, which under normal load
        // never builds up. If we ever do see backlog the store's
        // `droppedSinceLaunch()` counter surfaces it in diagnostics.
        let target = store
        Task.detached(priority: .utility) { [target] in
            await target.append(record)
        }
    }

    // MARK: - Helpers

    private static func toLogLevel(_ level: Logger.Level) -> LogLevel {
        switch level {
        case .trace: return .trace
        case .debug: return .debug
        case .info: return .info
        case .notice: return .notice
        case .warning: return .warning
        case .error: return .error
        case .critical: return .critical
        }
    }

    /// Convert a `swift-log` `MetadataValue` into our `AnyCodableJSON`
    /// so the OTel record stays JSON-clean. `stringConvertible` and
    /// `string` collapse to `.string`; `array` and `dictionary` recurse;
    /// `bool` / numeric primitives flow through with type preserved.
    private static func convert(_ value: Logger.Metadata.Value) -> AnyCodableJSON {
        switch value {
        case .string(let s):
            return .string(s)
        case .stringConvertible(let s):
            return .string(s.description)
        case .array(let arr):
            return .array(arr.map(convert))
        case .dictionary(let dict):
            var obj: [String: AnyCodableJSON] = [:]
            obj.reserveCapacity(dict.count)
            for (k, v) in dict {
                obj[k] = convert(v)
            }
            return .object(obj)
        }
    }
}
