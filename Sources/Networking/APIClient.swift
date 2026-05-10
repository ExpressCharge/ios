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
import Logging
import Models

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Module-private logger. swift-log façade — backed by the
/// `MultiplexLogHandler([OSLogHandler, RingBufferJSONLogHandler])`
/// installed by `LoggingBootstrap.bootstrap(...)` at app launch, so
/// records land in Console.app AND ride the sync envelope to the
/// server's `device_logs` table.
private let netLog = Logger(label: "network")

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
    /// Invoked on transport errors and sustained 5xx so a connectivity
    /// monitor can react immediately. Optional — tests pass nothing.
    private let failureReporter: (@Sendable () -> Void)?

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
        idempotencyKeyFactory: @escaping @Sendable () -> String = { UUID().uuidString },
        failureReporter: (@Sendable () -> Void)? = nil
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.tokenSource = tokenSource
        self.userAgent = userAgent
        self.idempotencyKeyFactory = idempotencyKeyFactory
        self.failureReporter = failureReporter

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
            let detail = String(describing: error)
            netLog.error(
                "APIClient.request: decode failed",
                metadata: [
                    "path": "\(endpoint.path)",
                    "detail": "\(detail)",
                ]
            )
            throw APIError.decode(detail: detail)
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
            let detail: String
            if let urlError = error as? URLError {
                detail = "\(urlError.code.rawValue) \(urlError.localizedDescription)"
            } else {
                detail = String(describing: error)
            }
            netLog.error(
                "APIClient.rawRequest: transport failed",
                metadata: [
                    "method": "\(endpoint.method.rawValue)",
                    "path": "\(endpoint.path)",
                    "detail": "\(detail)",
                ]
            )
            failureReporter?()
            throw APIError.network(detail: detail)
        }

        guard let http = response as? HTTPURLResponse else {
            netLog.error(
                "APIClient.rawRequest: non-HTTP response",
                metadata: ["path": "\(endpoint.path)"]
            )
            failureReporter?()
            throw APIError.network(detail: "non-HTTP response")
        }

        netLog.debug(
            "APIClient.rawRequest: response",
            metadata: [
                "method": "\(endpoint.method.rawValue)",
                "path": "\(endpoint.path)",
                "status": "\(http.statusCode)",
            ]
        )

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
                envelope.error == "invalid_nonce"
            {
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
            failureReporter?()
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
            throw APIError.network(detail: "URL components failed for \(endpoint.path)")
        }
        if !endpoint.queryItems.isEmpty {
            components.queryItems = endpoint.queryItems
        }
        guard let url = components.url else {
            throw APIError.network(detail: "URL build failed for \(endpoint.path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = endpoint.body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try body(encoder)
            } catch {
                throw APIError.decode(detail: "request body encode: \(String(describing: error))")
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
