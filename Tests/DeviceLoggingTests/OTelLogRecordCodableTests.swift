//
//  OTelLogRecordCodableTests.swift
//  DeviceLoggingTests
//
//  Pins the on-the-wire JSON shape of `OTelLogRecord` to a golden
//  fixture. If this test breaks, the server-side `device_logs` ingest
//  schema (Phase 3c) MUST be updated in lockstep — the wire format is
//  the load-bearing contract for the entire Phase 3 pipeline.
//

import Foundation
import Models
import Testing

@testable import DeviceLogging

@Suite("OTelLogRecord wire format")
struct OTelLogRecordCodableTests {

    @Test func encodesToCanonicalOTelKeys() throws {
        let record = OTelLogRecord(
            timestamp: 1_700_000_000_000_000_000,
            observedTimestamp: 1_700_000_000_500_000_000,
            severityText: "WARN",
            severityNumber: 13,
            body: "scan completed",
            attributes: [
                "expresscharge.seq": .string("42"),
                "category": .string("scan"),
                "duration_ms": .int(412),
            ],
            resource: [
                "service.name": "ExpresScan-iOS",
                "service.version": "1.4.2",
                "device.id": "abc-123",
                "os.name": "iOS",
                "os.version": "26.0",
            ]
        )
        let data = try JSONEncoder().encode(record)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        // Spec-pinned snake_case keys.
        #expect(object["timestamp"] as? Int64 == 1_700_000_000_000_000_000)
        #expect(object["observed_timestamp"] as? Int64 == 1_700_000_000_500_000_000)
        #expect(object["severity_text"] as? String == "WARN")
        #expect(object["severity_number"] as? Int == 13)
        #expect(object["body"] as? String == "scan completed")

        let attributes = try #require(object["attributes"] as? [String: Any])
        #expect(attributes["expresscharge.seq"] as? String == "42")
        #expect(attributes["category"] as? String == "scan")
        #expect(attributes["duration_ms"] as? Int == 412)

        let resource = try #require(object["resource"] as? [String: Any])
        #expect(resource["service.name"] as? String == "ExpresScan-iOS")
    }

    @Test func roundTripsLossless() throws {
        let original = OTelLogRecord(
            timestamp: 42,
            observedTimestamp: 100,
            severityText: "ERROR",
            severityNumber: 17,
            body: "boom",
            attributes: ["x": .bool(true), "y": .double(3.14)],
            resource: ["a": "b"],
            traceId: "0123456789abcdef0123456789abcdef",
            spanId: "0123456789abcdef"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OTelLogRecord.self, from: data)
        #expect(decoded == original)
    }

    @Test func severityMappingMatchesOTelSpec() {
        #expect(OTelSeverity.number(for: .trace) == 1)
        #expect(OTelSeverity.number(for: .debug) == 5)
        #expect(OTelSeverity.number(for: .info) == 9)
        #expect(OTelSeverity.number(for: .warning) == 13)
        #expect(OTelSeverity.number(for: .error) == 17)
        #expect(OTelSeverity.number(for: .critical) == 21)

        #expect(OTelSeverity.text(for: .trace) == "TRACE")
        #expect(OTelSeverity.text(for: .debug) == "DEBUG")
        #expect(OTelSeverity.text(for: .info) == "INFO")
        #expect(OTelSeverity.text(for: .warning) == "WARN")
        #expect(OTelSeverity.text(for: .error) == "ERROR")
        #expect(OTelSeverity.text(for: .critical) == "FATAL")
    }
}
