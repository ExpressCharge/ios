//
//  OTelLogRecord.swift
//  DeviceLogging
//
//  Wire-shape mirror of the OpenTelemetry Logs Data Model. The same
//  shape is emitted by both the iOS app (via `swift-log` +
//  `RingBufferJSONLogHandler`) and the expresscharge server (via Pino
//  with OTel-shaped formatters). The server's `device_logs` table
//  (migration 0053) is denormalised against this model.
//
//  The OTel `seq` concept doesn't exist; we tunnel our per-device
//  monotonic UInt64 idempotency key through `attributes["expresscharge.seq"]`
//  as a STRING (UInt64 doesn't fit in JS Number — string-encoding
//  preserves precision across the JSON boundary). The server stores
//  it as `numeric(20,0)` and uses `(device_id, seq)` as the PK.
//

import Foundation
import Models

/// One OTel-shaped log record. JSON keys mirror the OTel spec
/// (snake_case) — `severity_text`, `severity_number`, `observed_timestamp`.
public struct OTelLogRecord: Sendable, Equatable, Codable {

    /// Event time on the producer, **nanoseconds since the Unix epoch**.
    /// Stored as `Int64` to match OTel's wire shape; clients with
    /// millisecond-precision clocks just left-shift by 1e6.
    public var timestamp: Int64

    /// Ingest time. The handler stamps this when building the record,
    /// alongside `timestamp`. Server-side this is replaced by the DB's
    /// `now()` at insert.
    public var observedTimestamp: Int64

    public var severityText: String
    public var severityNumber: Int

    /// Free-form human message. PII redacted by `LogScrubber` before
    /// the handler writes the record to disk.
    public var body: String

    /// Structured context. Always carries `expresscharge.seq` (string-encoded
    /// UInt64) and `category` (the `swift-log` Logger label). Other keys
    /// are call-site supplied via `Logger.metadata` and follow OTel
    /// semantic conventions where possible.
    public var attributes: [String: AnyCodableJSON]

    /// Per-process constants — `service.name`, `service.version`,
    /// `device.id`, `os.name`, `os.version`. Populated by
    /// `ResourceProvider`; identical for every record from a given
    /// process boot.
    public var resource: [String: String]

    /// W3C Trace Context propagation — null when no active span. We
    /// don't emit traces today, but the field is here so a future
    /// migration to a full OTel SDK doesn't churn the schema.
    public var traceId: String?
    public var spanId: String?

    public init(
        timestamp: Int64,
        observedTimestamp: Int64,
        severityText: String,
        severityNumber: Int,
        body: String,
        attributes: [String: AnyCodableJSON] = [:],
        resource: [String: String] = [:],
        traceId: String? = nil,
        spanId: String? = nil
    ) {
        self.timestamp = timestamp
        self.observedTimestamp = observedTimestamp
        self.severityText = severityText
        self.severityNumber = severityNumber
        self.body = body
        self.attributes = attributes
        self.resource = resource
        self.traceId = traceId
        self.spanId = spanId
    }

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case observedTimestamp = "observed_timestamp"
        case severityText = "severity_text"
        case severityNumber = "severity_number"
        case body
        case attributes
        case resource
        case traceId = "trace_id"
        case spanId = "span_id"
    }
}

// MARK: - Severity mapping

/// Maps `Logging.Logger.Level` ↔ OTel severity. The text/number values
/// are pinned by the OTel spec; do not remap.
public enum OTelSeverity: Sendable {

    /// OTel severity_number for a `swift-log` level. `swift-log` has 7
    /// levels; we collapse `notice`/`info` and `critical`/`error` onto
    /// the OTel buckets the server actually stores (DEBUG/INFO/WARN/
    /// ERROR/FATAL). `trace` falls into the `TRACE` bucket (severity 1)
    /// even though the server schema today doesn't index it; better to
    /// preserve the wire fidelity than to round-trip-lose it.
    public static func number(for level: LogLevel) -> Int {
        switch level {
        case .trace: return 1
        case .debug: return 5
        case .info: return 9
        case .notice: return 9        // OTel maps NOTICE onto INFO bucket.
        case .warning: return 13
        case .error: return 17
        case .critical: return 21
        }
    }

    /// OTel severity_text for a `swift-log` level. Always uppercase.
    public static func text(for level: LogLevel) -> String {
        switch level {
        case .trace: return "TRACE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        case .critical: return "FATAL"
        }
    }
}

/// Mirror of `Logging.Logger.Level` so this module doesn't have to
/// expose its `swift-log` dependency to consumers that just want to
/// build records by hand (tests, fixtures, the `DiagnosticsSheet`
/// renderer).
public enum LogLevel: String, Sendable, Equatable, Codable, CaseIterable {
    case trace
    case debug
    case info
    case notice
    case warning
    case error
    case critical

    /// Inverse of `OTelSeverity.text(for:)` — normalises an OTel
    /// `severity_text` string back to a `LogLevel` for the sheet's
    /// colour mapping. Unknown strings fall back to `.info`.
    public static func from(severityText text: String) -> LogLevel {
        switch text.uppercased() {
        case "TRACE": return .trace
        case "DEBUG": return .debug
        case "INFO": return .info
        case "WARN", "WARNING": return .warning
        case "ERROR": return .error
        case "FATAL", "CRITICAL": return .critical
        default: return .info
        }
    }
}
