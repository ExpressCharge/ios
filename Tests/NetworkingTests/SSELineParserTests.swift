//
//  SSELineParserTests.swift
//  NetworkingTests
//
//  Unit tests for the SSE byte parser.
//

import Foundation
import Testing

@testable import Networking

/// Feeds an SSE-shaped string through the parser. Note: Swift multiline
/// string literals strip the final newline before `"""`, so a literal that
/// looks like it ends with a blank line actually ends with one `\n`. Tests
/// pass `endWithBlankLine: true` (default) to add the second `\n` that
/// terminates the event block.
private func feed(_ string: String, endWithBlankLine: Bool = true) -> [SSEEvent] {
    var parser = SSELineParser()
    var events: [SSEEvent] = []
    let input = endWithBlankLine ? string + "\n" : string
    for byte in input.utf8 {
        if let event = parser.consume(byte: byte) {
            events.append(event)
        }
    }
    return events
}

@Suite("SSE line parser")
struct SSELineParserTests {

    @Test func parsesSingleEvent() {
        let raw = """
            event: scan.requested
            id: 1235
            data: {"deviceId":"abc"}

            """
        let events = feed(raw)
        #expect(events.count == 1)
        #expect(events[0].event == "scan.requested")
        #expect(events[0].id == "1235")
        #expect(events[0].data == #"{"deviceId":"abc"}"#)
    }

    @Test func defaultEventNameIsMessage() {
        let raw = """
            data: hello

            """
        let events = feed(raw)
        #expect(events.count == 1)
        #expect(events[0].event == "message")
        #expect(events[0].data == "hello")
    }

    @Test func multipleDataLinesJoinWithNewline() {
        let raw = """
            event: x
            data: line one
            data: line two

            """
        let events = feed(raw)
        #expect(events.count == 1)
        #expect(events[0].data == "line one\nline two")
    }

    @Test func commentLinesAreIgnored() {
        let raw = """
            : keepalive
            event: ping
            data: {}

            """
        let events = feed(raw)
        #expect(events.count == 1)
        #expect(events[0].event == "ping")
    }

    @Test func valueOptionallyStartsWithSpace() {
        let raw = "data:no-space\n\ndata: with-space\n\n"
        let events = feed(raw)
        #expect(events.count == 2)
        #expect(events[0].data == "no-space")
        #expect(events[1].data == "with-space")
    }

    @Test func handlesCRLFLineEndings() {
        let raw = "event: x\r\ndata: y\r\n\r\n"
        let events = feed(raw)
        #expect(events.count == 1)
        #expect(events[0].event == "x")
        #expect(events[0].data == "y")
    }

    @Test func idPersistsWhenFollowingEventOmitsIt() {
        let raw = """
            event: a
            id: 1
            data: x

            event: b
            data: y

            """
        let events = feed(raw)
        #expect(events.count == 2)
        #expect(events[0].id == "1")
        // Per spec, the parser's "last event ID" persists even when the
        // next event doesn't repeat `id:` — it's still '1' until reset.
        #expect(events[1].id == "1")
    }

    @Test func multipleEventsInOneFeed() {
        let raw = """
            event: a
            data: 1

            event: b
            data: 2

            event: c
            data: 3

            """
        let events = feed(raw)
        #expect(events.map(\.event) == ["a", "b", "c"])
        #expect(events.map(\.data) == ["1", "2", "3"])
    }

    @Test func emptyBufferEmitsNothing() {
        let events = feed("\n\n\n")
        #expect(events.count == 0)
    }
}
