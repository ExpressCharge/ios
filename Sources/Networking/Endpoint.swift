//
//  Endpoint.swift
//  Networking
//
//  Describes a single HTTP request the iOS app wants to send. Composed by
//  feature-level helpers and consumed by `APIClient.request(_:)`.
//

import Foundation

/// HTTP method. Restricted to the verbs the expresscan API uses.
public enum HTTPMethod: String, Sendable, Equatable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"

    /// Whether the method is "state-changing" — used to decide whether to
    /// auto-attach an `Idempotency-Key`.
    public var isStateChanging: Bool {
        switch self {
        case .post, .put, .delete: return true
        case .get: return false
        }
    }
}

/// A request to be dispatched by `APIClient`.
///
/// `body` is an opaque encodable payload. The endpoint constructor accepts
/// any concrete `Encodable & Sendable` and stores a closure that produces
/// the encoded `Data` lazily — keeping `Endpoint` itself `Sendable` without
/// forcing existential `Encodable` (which is non-`Sendable`).
public struct Endpoint: Sendable {
    public let path: String
    public let method: HTTPMethod
    public let requiresAuth: Bool
    public let idempotencyKey: String?
    public let queryItems: [URLQueryItem]
    public let extraHeaders: [String: String]

    /// Lazily encodes the body. `nil` means no body.
    public let body: (@Sendable (JSONEncoder) throws -> Data)?

    public init(
        path: String,
        method: HTTPMethod,
        requiresAuth: Bool = true,
        idempotencyKey: String? = nil,
        queryItems: [URLQueryItem] = [],
        extraHeaders: [String: String] = [:],
        body: (@Sendable (JSONEncoder) throws -> Data)? = nil
    ) {
        self.path = path
        self.method = method
        self.requiresAuth = requiresAuth
        self.idempotencyKey = idempotencyKey
        self.queryItems = queryItems
        self.extraHeaders = extraHeaders
        self.body = body
    }

    /// Convenience: build an endpoint from a concrete `Encodable` body.
    public static func with<Body: Encodable & Sendable>(
        path: String,
        method: HTTPMethod,
        requiresAuth: Bool = true,
        idempotencyKey: String? = nil,
        queryItems: [URLQueryItem] = [],
        extraHeaders: [String: String] = [:],
        body: Body
    ) -> Endpoint {
        Endpoint(
            path: path,
            method: method,
            requiresAuth: requiresAuth,
            idempotencyKey: idempotencyKey,
            queryItems: queryItems,
            extraHeaders: extraHeaders,
            body: { encoder in try encoder.encode(body) }
        )
    }
}
