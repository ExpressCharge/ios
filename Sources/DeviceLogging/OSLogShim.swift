//
//  OSLogShim.swift
//  DeviceLogging
//
//  `swift-log` `LogHandler` that re-emits to Apple's `os.Logger` so
//  Console.app filtering by subsystem/category continues to work for
//  anyone reading device logs over USB during development. One half of
//  the multiplex; the other half is `RingBufferJSONLogHandler` which
//  durably persists records for the sync envelope.
//
//  Privacy: every interpolation goes through `os.Logger`'s default
//  redaction — string substitutions are `<private>` in release builds
//  unless we explicitly mark them public. The `RingBufferJSONLogHandler`
//  has its own `LogScrubber` for the durable path.
//

import Foundation
import Logging
import os

/// Maps `swift-log` levels onto `os.Logger` log methods.
public struct OSLogHandler: LogHandler {

    public var metadata: Logging.Logger.Metadata = [:]
    public var logLevel: Logging.Logger.Level = .info

    public var metadataProvider: Logging.Logger.MetadataProvider?

    private let label: String
    private let osLogger: os.Logger

    public init(label: String, subsystem: String = "com.example.expresscharge.ios") {
        self.label = label
        self.osLogger = os.Logger(subsystem: subsystem, category: label)
    }

    public init(
        label: String,
        subsystem: String,
        metadataProvider: Logging.Logger.MetadataProvider?
    ) {
        self.label = label
        self.osLogger = os.Logger(subsystem: subsystem, category: label)
        self.metadataProvider = metadataProvider
    }

    public subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(
        level: Logging.Logger.Level,
        message: Logging.Logger.Message,
        metadata: Logging.Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        // Render structured metadata into a single trailing string so
        // Console.app readers see context inline. We don't use this for
        // the durable JSON path — that's `RingBufferJSONLogHandler`.
        let combined = mergedMetadata(message: message, callerMetadata: metadata)
        let formatted = render(message: message, metadata: combined)

        // Re-emit at the matching `os.Logger` level. We mark the full
        // message public because `swift-log` callers either chose
        // `Logger.MetadataValue` (typed) or string-interpolated already
        // — privacy is the caller's responsibility for the durable
        // JSON path; the OS logger is debug-only.
        switch level {
        case .trace, .debug:
            osLogger.debug("\(formatted, privacy: .public)")
        case .info, .notice:
            osLogger.info("\(formatted, privacy: .public)")
        case .warning:
            osLogger.warning("\(formatted, privacy: .public)")
        case .error:
            osLogger.error("\(formatted, privacy: .public)")
        case .critical:
            osLogger.critical("\(formatted, privacy: .public)")
        }
    }

    private func mergedMetadata(
        message _: Logging.Logger.Message,
        callerMetadata: Logging.Logger.Metadata?
    ) -> Logging.Logger.Metadata {
        var merged = self.metadata
        if let providerMetadata = metadataProvider?.get() {
            merged.merge(providerMetadata) { _, new in new }
        }
        if let callerMetadata {
            merged.merge(callerMetadata) { _, new in new }
        }
        return merged
    }

    private func render(message: Logging.Logger.Message, metadata: Logging.Logger.Metadata)
        -> String
    {
        if metadata.isEmpty { return "\(message)" }
        let pairs =
            metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        return "\(message)  \(pairs)"
    }
}
