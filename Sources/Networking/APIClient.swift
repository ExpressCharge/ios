//
//  APIClient.swift
//  Networking
//
//  Single generic entry point for HTTP requests against the expresscharge
//  backend. Header rules:
//
//   - `Authorization: Bearer <token>` when the endpoint declares
//     `requiresAuth = true`. The token comes from a closure injected at
//     construction time (so testing can stub the token without depending
//     on AuthCore's keychain singleton).
//   - `Idempotency-Key: <uuid>` on POST/PUT/DELETE. The endpoint may
//     supply its own value; otherwise a fresh UUID is generated.
//   - `Accept: application/json` always.
//   - `Content-Type: application/json` when there is a body.
//

import Foundation
import os

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

import Models

/// Module-private logger. Mirrors the App target's `netLog` subsystem so
/// requests + responses land in the same Console.app stream as the app's
/// own networking events.
private let netLog = Logger(subsystem: "gg.vlad.expresscan", category: "network")

// MARK: - HTTP transport abstraction

/// Minimal slice of `URLSession` we depend on, so tests can stub via a
/// `URLProtocol` subclass passed to a real `URLSession` instance.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}

// MARK: - APIClient

/// Async/await HTTP client tuned for the expresscharge API.
public actor APIClient {

    // MARK: Configuration

    /// The API host. `nonisolated` so actor-external callers (e.g.
    /// `EventStreamReconnector` building an SSE URL) can read it
    /// without crossing the actor's executor.
    public nonisolated let baseURL: URL
    private let transport: HTTPTransport
    private let tokenSource: @Sendable () async -> String?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let userAgent: String?
    private let idempotencyKeyFactory: @Sendable () -> String

    /// Designated initialiser.
    ///
    /// - Parameters:
    ///   - baseURL: e.g. `URL(string: "https://manage.example.com")!`.
    ///   - transport: An `HTTPTransport` (defaults to `URLSession.shared`).
    ///   - tokenSource: Closure that returns the current bearer token, or
    ///     `nil` if none. Called on each request so token rotation Just
    ///     Works.
    ///   - userAgent: Optional `User-Agent` header (e.g.
    ///     `"ExpresScan/1.0 (iOS 17.4)"`).
    ///   - idempotencyKeyFactory: Override for tests; defaults to
    ///     `UUID().uuidString`.
    public init(
        baseURL: URL,
        transport: HTTPTransport = URLSession.shared,
        tokenSource: @escaping @Sendable () async -> String?,
        userAgent: String? = nil,
        idempotencyKeyFactory: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.tokenSource = tokenSource
        self.userAgent = userAgent
        self.idempotencyKeyFactory = idempotencyKeyFactory

        let encoder = JSONEncoder()
        // Wire is camelCase already (matches TS source of truth) — leave
        // keys untouched.
        encoder.keyEncodingStrategy = .useDefaultKeys
        // The TS server emits ISO-8601 date strings (Date.toISOString()).
        // Without explicit strategy, JSONEncoder ships dates as
        // reference-date doubles, which the server rejects.
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: Public API

    /// Execute an endpoint and decode its JSON body into `T`.
    public func request<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let data = try await rawRequest(endpoint)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // Surface the underlying DecodingError before flattening to
            // APIError.decode — without this, response-shape drift is
            // invisible to anyone reading the console.
            netLog.error("APIClient.request: decode failed for \(endpoint.path, privacy: .public): \(String(describing: error), privacy: .public)")
            throw APIError.decode
        }
    }

    /// Execute an endpoint that returns no body (or an ignorable body).
    public func send(_ endpoint: Endpoint) async throws {
        _ = try await rawRequest(endpoint)
    }

    // MARK: - Internals

    /// Builds, dispatches, and validates the response. Returns the raw
    /// body on 2xx; throws an `APIError` otherwise.
    func rawRequest(_ endpoint: Endpoint) async throws -> Data {
        let urlRequest = try await buildURLRequest(endpoint)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: urlRequest)
        } catch {
            netLog.error("APIClient.rawRequest: transport failed for \(endpoint.method.rawValue, privacy: .public) \(endpoint.path, privacy: .public): \(String(describing: error), privacy: .public)")
            throw APIError.network
        }

        guard let http = response as? HTTPURLResponse else {
            netLog.error("APIClient.rawRequest: non-HTTP response for \(endpoint.path, privacy: .public)")
            throw APIError.network
        }

        netLog.debug("APIClient.rawRequest: \(endpoint.method.rawValue, privacy: .public) \(endpoint.path, privacy: .public) → \(http.statusCode, privacy: .public)")

        switch http.statusCode {
        case 200..<300:
            return data
        case 400:
            // Some endpoints return structured error codes. Surface the
            // two we care about (clock_skew, invalid_nonce) explicitly.
            if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data) {
                switch envelope.error {
                case "clock_skew":
                    throw APIError.clockSkew
                case "invalid_nonce":
                    throw APIError.invalidNonce
                default:
                    throw APIError.server(statusCode: 400, errorCode: envelope.error)
                }
            }
            throw APIError.server(statusCode: 400, errorCode: nil)
        case 401:
            // 401 with `error: "invalid_nonce"` should map to .invalidNonce.
            if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data),
               envelope.error == "invalid_nonce" {
                throw APIError.invalidNonce
            }
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 410:
            throw APIError.gone
        case 429:
            throw APIError.rateLimited
        case 500..<600:
            let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data)
            throw APIError.server(statusCode: http.statusCode, errorCode: envelope?.error)
        default:
            throw APIError.server(statusCode: http.statusCode, errorCode: nil)
        }
    }

    private func buildURLRequest(_ endpoint: Endpoint) async throws -> URLRequest {
        guard
            var components = URLComponents(
                url: baseURL.appendingPathComponent(endpoint.path),
                resolvingAgainstBaseURL: false
            )
        else {
            throw APIError.network
        }
        if !endpoint.queryItems.isEmpty {
            components.queryItems = endpoint.queryItems
        }
        guard let url = components.url else {
            throw APIError.network
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = endpoint.body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try body(encoder)
            } catch {
                throw APIError.decode
            }
        }

        if endpoint.method.isStateChanging {
            let key = endpoint.idempotencyKey ?? idempotencyKeyFactory()
            request.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        }

        if endpoint.requiresAuth {
            if let token = await tokenSource() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } else {
                throw APIError.unauthorized
            }
        }

        if let userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }

        for (name, value) in endpoint.extraHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }

        return request
    }
}
