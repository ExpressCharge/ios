//
//  LogScrubberTests.swift
//  DeviceLoggingTests
//
//  Pins the iOS-side PII deny-list. Server-side mirror at
//  `expresscharge/src/lib/utils/log_scrubber.ts` shares the same regex
//  set and fixtures (`docs/logging/scrubber-fixtures.json`).
//

import Foundation
import Models
import Testing

@testable import DeviceLogging

@Suite("LogScrubber")
struct LogScrubberTests {

    @Test func redactsEmailInBody() {
        var record = make(body: "user accounts@vlad.gg signed in")
        LogScrubber.scrub(&record)
        #expect(record.body == "user <email> signed in")
    }

    @Test func redactsBearerTokenInBody() {
        var record = make(body: "Authorization: Bearer abcd1234efgh5678")
        LogScrubber.scrub(&record)
        #expect(record.body.contains("Bearer <token>"))
        #expect(!record.body.contains("abcd1234efgh5678"))
    }

    @Test func redactsJWT() {
        var record = make(
            body: "header eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.abc123 trailing"
        )
        LogScrubber.scrub(&record)
        #expect(record.body.contains("<jwt>"))
        #expect(!record.body.contains("eyJhbGc"))
    }

    @Test func redactsE164Phone() {
        var record = make(body: "ring +14155551234 now")
        LogScrubber.scrub(&record)
        #expect(record.body.contains("<phone>"))
    }

    @Test func wholesaleRedactsAuthorizationAttribute() {
        var record = make(
            body: "ok",
            attributes: ["Authorization": .string("Bearer xxxxxxxxx")]
        )
        LogScrubber.scrub(&record)
        if case .string(let s) = record.attributes["Authorization"] {
            #expect(s == "<redacted>")
        } else {
            Issue.record("Authorization should be string-redacted")
        }
    }

    @Test func wholesaleRedactsCardKeys() {
        var record = make(
            body: "ok",
            attributes: ["card_uid": .string("0411AABB12CC80")]
        )
        LogScrubber.scrub(&record)
        if case .string(let s) = record.attributes["card_uid"] {
            #expect(s == "<redacted>")
        } else {
            Issue.record("card_uid should be string-redacted")
        }
    }

    @Test func resourceLeftIntact() {
        var record = make(
            body: "ok",
            resource: ["service.name": "ExpresScan-iOS", "device.id": "abc"]
        )
        LogScrubber.scrub(&record)
        #expect(record.resource["service.name"] == "ExpresScan-iOS")
        #expect(record.resource["device.id"] == "abc")
    }

    @Test func recursivelyScrubsNestedAttributeStrings() {
        var record = make(
            body: "ok",
            attributes: [
                "context": .object([
                    "user": .string("accounts@vlad.gg"),
                    "trace": .array([.string("Bearer abcdefghij")]),
                ])
            ]
        )
        LogScrubber.scrub(&record)
        guard case .object(let context) = record.attributes["context"] else {
            Issue.record("context should remain an object")
            return
        }
        if case .string(let user) = context["user"] {
            #expect(user == "<email>")
        }
        if case .array(let trace) = context["trace"], case .string(let s) = trace.first {
            #expect(s.contains("Bearer <token>"))
        }
    }

    // MARK: - Fixture

    private func make(
        body: String,
        attributes: [String: AnyCodableJSON] = [:],
        resource: [String: String] = [:]
    ) -> OTelLogRecord {
        OTelLogRecord(
            timestamp: 1,
            observedTimestamp: 1,
            severityText: "INFO",
            severityNumber: 9,
            body: body,
            attributes: attributes,
            resource: resource
        )
    }
}
