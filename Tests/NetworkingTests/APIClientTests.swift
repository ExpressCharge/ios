//
//  APIClientTests.swift
//  NetworkingTests
//
//  Stubs `URLSession` via a `URLProtocol` subclass to assert the status-
//  code → APIError mapping plus header / body shaping rules.
//

import Foundation
import Testing

@testable import Models
@testable import Networking

private struct Echo: Decodable, Equatable {
    let ok: Bool
}

private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeClient(
    session: URLSession,
    token: String? = "dev_token"
) -> APIClient {
    APIClient(
        baseURL: URL(string: "https://example.test")!,
        transport: session,
        tokenSource: { token },
        idempotencyKeyFactory: { "fixed-uuid-1234" }
    )
}

// Each test resets the stub state in a `defer` to avoid cross-test pollution.
// `StubURLProtocol` keeps global mutable state, so we serialize the suite
// to keep parallel test workers from stomping on each other.

@Suite("APIClient", .serialized)
struct APIClientTests {

    @Test func decodesBodyOn200() async throws {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in
            (200, ["Content-Type": "application/json"], Data(#"{"ok":true}"#.utf8))
        }
        let client = makeClient(session: makeSession())
        let endpoint = Endpoint(path: "/api/devices/me", method: .get)
        let result: Echo = try await client.request(endpoint)
        #expect(result == Echo(ok: true))
    }

    @Test func mapsUnauthorized() async {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in (401, [:], Data()) }
        let client = makeClient(session: makeSession())
        await #expect(throws: APIError.unauthorized) {
            let _: Echo = try await client.request(Endpoint(path: "/x", method: .get))
        }
    }

    @Test func mapsForbidden() async {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in (403, [:], Data()) }
        let client = makeClient(session: makeSession())
        await #expect(throws: APIError.forbidden) {
            let _: Echo = try await client.request(Endpoint(path: "/x", method: .get))
        }
    }

    @Test func mapsNotFound() async {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in (404, [:], Data()) }
        let client = makeClient(session: makeSession())
        await #expect(throws: APIError.notFound) {
            let _: Echo = try await client.request(Endpoint(path: "/x", method: .get))
        }
    }

    @Test func mapsGone() async {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in (410, [:], Data()) }
        let client = makeClient(session: makeSession())
        await #expect(throws: APIError.gone) {
            let _: Echo = try await client.request(Endpoint(path: "/x", method: .get))
        }
    }

    @Test func mapsRateLimited() async {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in (429, [:], Data()) }
        let client = makeClient(session: makeSession())
        await #expect(throws: APIError.rateLimited) {
            let _: Echo = try await client.request(Endpoint(path: "/x", method: .get))
        }
    }

    @Test func maps500WithStatus() async {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in
            (502, [:], Data(#"{"error":"upstream"}"#.utf8))
        }
        let client = makeClient(session: makeSession())
        await #expect(throws: APIError.server(statusCode: 502, errorCode: "upstream")) {
            let _: Echo = try await client.request(Endpoint(path: "/x", method: .get))
        }
    }

    @Test func maps400ClockSkew() async {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in
            (
                400, ["Content-Type": "application/json"],
                Data(#"{"error":"clock_skew"}"#.utf8)
            )
        }
        let client = makeClient(session: makeSession())
        await #expect(throws: APIError.clockSkew) {
            let _: Echo = try await client.request(Endpoint(path: "/x", method: .post))
        }
    }

    @Test func maps401InvalidNonce() async {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in
            (
                401, ["Content-Type": "application/json"],
                Data(#"{"error":"invalid_nonce"}"#.utf8)
            )
        }
        let client = makeClient(session: makeSession())
        await #expect(throws: APIError.invalidNonce) {
            let _: Echo = try await client.request(Endpoint(path: "/x", method: .post))
        }
    }

    @Test func mapsMalformedJsonToDecode() async {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in
            (200, [:], Data("not json".utf8))
        }
        let client = makeClient(session: makeSession())
        await #expect(throws: APIError.decode) {
            let _: Echo = try await client.request(Endpoint(path: "/x", method: .get))
        }
    }

    // MARK: - Header rules

    @Test func attachesAuthorizationHeader() async throws {
        defer { StubURLProtocol.reset() }
        // Capture the request header on a thread-safe lock since the
        // closure may run off the main actor.
        let captured = LockBox<URLRequest?>(nil)
        StubURLProtocol.handler = { req in
            captured.set(req)
            return (200, [:], Data(#"{"ok":true}"#.utf8))
        }
        let client = makeClient(session: makeSession(), token: "dev_xyz")
        let endpoint = Endpoint(path: "/api/devices/me", method: .get)
        let _: Echo = try await client.request(endpoint)

        #expect(
            captured.get()?.value(forHTTPHeaderField: "Authorization")
                == "Bearer dev_xyz"
        )
    }

    @Test func throwsUnauthorizedWhenTokenMissing() async {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in (200, [:], Data(#"{"ok":true}"#.utf8)) }
        let client = makeClient(session: makeSession(), token: nil)
        await #expect(throws: APIError.unauthorized) {
            let _: Echo = try await client.request(Endpoint(path: "/x", method: .get))
        }
    }

    @Test func skipsAuthorizationWhenNotRequired() async throws {
        defer { StubURLProtocol.reset() }
        let captured = LockBox<URLRequest?>(nil)
        StubURLProtocol.handler = { req in
            captured.set(req)
            return (200, [:], Data(#"{"ok":true}"#.utf8))
        }
        let client = makeClient(session: makeSession(), token: nil)
        let endpoint = Endpoint(path: "/public", method: .get, requiresAuth: false)
        let _: Echo = try await client.request(endpoint)
        #expect(captured.get()?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func attachesIdempotencyKeyOnPost() async throws {
        defer { StubURLProtocol.reset() }
        let captured = LockBox<URLRequest?>(nil)
        StubURLProtocol.handler = { req in
            captured.set(req)
            return (200, [:], Data(#"{"ok":true}"#.utf8))
        }
        let client = makeClient(session: makeSession())
        let endpoint = Endpoint(
            path: "/api/devices/scan-result",
            method: .post,
            body: { _ in Data("{}".utf8) }
        )
        let _: Echo = try await client.request(endpoint)
        #expect(
            captured.get()?.value(forHTTPHeaderField: "Idempotency-Key")
                == "fixed-uuid-1234"
        )
        #expect(
            captured.get()?.value(forHTTPHeaderField: "Content-Type")
                == "application/json"
        )
    }

    @Test func skipsIdempotencyKeyOnGet() async throws {
        defer { StubURLProtocol.reset() }
        let captured = LockBox<URLRequest?>(nil)
        StubURLProtocol.handler = { req in
            captured.set(req)
            return (200, [:], Data(#"{"ok":true}"#.utf8))
        }
        let client = makeClient(session: makeSession())
        let _: Echo = try await client.request(Endpoint(path: "/x", method: .get))
        #expect(captured.get()?.value(forHTTPHeaderField: "Idempotency-Key") == nil)
    }

    @Test func endpointSuppliedIdempotencyKeyWins() async throws {
        defer { StubURLProtocol.reset() }
        let captured = LockBox<URLRequest?>(nil)
        StubURLProtocol.handler = { req in
            captured.set(req)
            return (200, [:], Data(#"{"ok":true}"#.utf8))
        }
        let client = makeClient(session: makeSession())
        let endpoint = Endpoint(
            path: "/x",
            method: .post,
            idempotencyKey: "explicit-key"
        )
        let _: Echo = try await client.request(endpoint)
        #expect(
            captured.get()?.value(forHTTPHeaderField: "Idempotency-Key")
                == "explicit-key"
        )
    }

    @Test func networkFailureMapsToNetwork() async {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.failureMode = .networkError
        let client = makeClient(session: makeSession())
        await #expect(throws: APIError.network) {
            let _: Echo = try await client.request(Endpoint(path: "/x", method: .get))
        }
    }
}

// MARK: - LockBox helper for thread-safe mutation across the URLProtocol callback

final class LockBox<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()

    init(_ initial: T) { self.value = initial }

    func get() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ new: T) {
        lock.lock()
        defer { lock.unlock() }
        value = new
    }
}

// MARK: - URLProtocol stub

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum FailureMode: Sendable {
        case none
        case networkError
    }

    nonisolated(unsafe) static var handler:
        (@Sendable (URLRequest) -> (Int, [String: String], Data))?
    nonisolated(unsafe) static var failureMode: FailureMode = .none

    static func reset() {
        handler = nil
        failureMode = .none
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        switch StubURLProtocol.failureMode {
        case .networkError:
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.notConnectedToInternet)
            )
            return
        case .none:
            break
        }

        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (status, headers, body) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
