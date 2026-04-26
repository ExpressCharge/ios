//
//  EventStreamService.swift
//  Networking
//
//  Server-Sent Events (SSE) byte parser, wrapping `URLSession.bytes(for:)`.
//
//  Reconnect / backoff is OUT of scope here — that lives in the higher
//  level `EventStreamReconnector` shipped by E-app-wire. This module only
//  emits a raw `AsyncThrowingStream<SSEEvent, Error>` and tracks the most
//  recent `id:` so the higher layer can use it for `Last-Event-ID`.
//
//  Spec: `50-ios.md` § "SSE client" and `20-contracts.md`
//  § "Endpoint detail: GET /api/devices/scan-stream".
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A parsed SSE event.
public struct SSEEvent: Sendable, Equatable {
    /// `event:` field. Defaults to `"message"` per the SSE spec.
    public let event: String
    /// Concatenated `data:` lines, joined with `\n` (per the spec).
    public let data: String
    /// `id:` field if present.
    public let id: String?

    public init(event: String, data: String, id: String?) {
        self.event = event
        self.data = data
        self.id = id
    }
}

/// Errors emitted into the stream.
public enum EventStreamError: Error, Equatable, Sendable {
    case unauthorized
    case gone
    case server(statusCode: Int)
    case network
}

// MARK: - Byte transport abstraction

/// Type-erased async byte stream. We don't depend on
/// `URLSession.AsyncBytes` directly because its definition varies across
/// platforms / SDK levels — e.g. on Linux Foundation it isn't part of the
/// public stable surface, and stubs in tests want a plain
/// `AsyncThrowingStream`.
public typealias ByteStream = AsyncThrowingStream<UInt8, Error>

/// Slice of `URLSession` we depend on for SSE byte streaming.
public protocol BytesTransport: Sendable {
    func sseBytes(for request: URLRequest) async throws -> (ByteStream, URLResponse)
}

extension URLSession: BytesTransport {
    public func sseBytes(
        for request: URLRequest
    ) async throws -> (ByteStream, URLResponse) {
        let (bytes, response) = try await self.bytes(for: request)
        let stream = ByteStream { continuation in
            let task = Task {
                do {
                    for try await byte in bytes {
                        continuation.yield(byte)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
        return (stream, response)
    }
}

// MARK: - EventStreamService

/// Streams SSE events from a single connection.
///
/// One instance == one connection. Re-create it to reconnect.
public actor EventStreamService {
    public let url: URL
    private let transport: BytesTransport
    private let tokenSource: @Sendable () async -> String?
    private var lastEventID: String?

    public init(
        url: URL,
        transport: BytesTransport = URLSession.shared,
        tokenSource: @escaping @Sendable () async -> String?,
        initialLastEventID: String? = nil
    ) {
        self.url = url
        self.transport = transport
        self.tokenSource = tokenSource
        self.lastEventID = initialLastEventID
    }

    /// Most recent `id:` field observed. The higher-level reconnector
    /// uses this for `Last-Event-ID` on a fresh connection.
    public func currentLastEventID() -> String? { lastEventID }

    /// Opens the SSE connection and returns an `AsyncThrowingStream` of
    /// events. Closing the stream (cancel/dismiss) tears down the
    /// connection automatically — `URLSession.bytes(for:)`'s
    /// `AsyncBytes` is cancellable.
    public func events() -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream<SSEEvent, Error> { continuation in
            let task = Task {
                do {
                    try await runStream(continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Internals

    private func runStream(
        continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // SSE responses must not be cached.
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        if let token = await tokenSource() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            throw EventStreamError.unauthorized
        }
        if let lastEventID {
            request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
        }

        let bytes: ByteStream
        let response: URLResponse
        do {
            (bytes, response) = try await transport.sseBytes(for: request)
        } catch {
            throw EventStreamError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw EventStreamError.network
        }

        switch http.statusCode {
        case 200..<300:
            break
        case 401:
            throw EventStreamError.unauthorized
        case 410:
            throw EventStreamError.gone
        default:
            throw EventStreamError.server(statusCode: http.statusCode)
        }

        var parser = SSELineParser()

        for try await byte in bytes {
            try Task.checkCancellation()
            if let event = parser.consume(byte: byte) {
                if let eid = event.id { lastEventID = eid }
                continuation.yield(event)
            }
        }
    }
}

// MARK: - Line parser

/// Stateful SSE byte parser. Feed it bytes one at a time; it emits a fully
/// parsed `SSEEvent` whenever a blank line is consumed (terminating an
/// event block).
///
/// Handles the canonical SSE wire format:
///
///     event: scan.requested
///     id: 1235
///     data: {"deviceId":"…"}
///     data: {"more":"data"}    ← multiple `data:` lines join with "\n"
///
///     : keepalive              ← comment lines (start with ':') are ignored
///
/// Line terminators may be `\n`, `\r\n`, or `\r`. The terminator after a
/// blank line ends the event block.
struct SSELineParser {
    private var lineBuffer: [UInt8] = []
    private var seenCR = false

    private var event: String?
    private var dataLines: [String] = []
    private var id: String?

    /// Feed one byte. Returns a fully parsed event when the parser
    /// finishes one (i.e. on the blank line that terminates an event
    /// block); otherwise returns `nil`.
    mutating func consume(byte: UInt8) -> SSEEvent? {
        // Normalise line endings: treat \r, \n, and \r\n as one terminator.
        if byte == 0x0D /* \r */ {
            seenCR = true
            return finishLine()
        }
        if byte == 0x0A /* \n */ {
            if seenCR {
                // \r\n — the \r already terminated the line. Skip the \n.
                seenCR = false
                return nil
            }
            return finishLine()
        }
        seenCR = false
        lineBuffer.append(byte)
        return nil
    }

    private mutating func finishLine() -> SSEEvent? {
        defer { lineBuffer.removeAll(keepingCapacity: true) }

        if lineBuffer.isEmpty {
            // Blank line → dispatch event (if we have any data).
            return dispatch()
        }

        let line = String(decoding: lineBuffer, as: UTF8.self)

        // Comment line.
        if line.hasPrefix(":") { return nil }

        // Field: value, with optional space after colon.
        let field: String
        let value: String
        if let colon = line.firstIndex(of: ":") {
            field = String(line[..<colon])
            var valueStart = line.index(after: colon)
            if valueStart < line.endIndex, line[valueStart] == " " {
                valueStart = line.index(after: valueStart)
            }
            value = String(line[valueStart...])
        } else {
            // No colon → entire line is field, value is empty.
            field = line
            value = ""
        }

        switch field {
        case "event":
            event = value
        case "data":
            dataLines.append(value)
        case "id":
            // Per the spec, an `id:` with the NUL character is invalid; we
            // accept any UTF-8 value, including empty.
            id = value
        case "retry":
            // Reconnect timing is the higher layer's call — ignore.
            break
        default:
            // Unknown field → ignore per spec.
            break
        }

        return nil
    }

    private mutating func dispatch() -> SSEEvent? {
        defer {
            event = nil
            dataLines.removeAll(keepingCapacity: true)
            // Note: `id` persists across events per spec ("last event ID").
        }
        guard !dataLines.isEmpty || event != nil else {
            return nil
        }
        return SSEEvent(
            event: event ?? "message",
            data: dataLines.joined(separator: "\n"),
            id: id
        )
    }
}
