//
//  APIError.swift
//  Networking
//
//  Error vocabulary for `APIClient`.
//

import Foundation

/// Outcome of a request that did not produce a successful, decodable
/// response. The cases are aligned with the HTTP status codes that the
/// expresscharge backend emits — see `20-contracts.md`.
public enum APIError: Error, Equatable, Sendable {
    /// 401. Bearer token was rejected; caller should clear keychain.
    case unauthorized
    /// 403. Caller is not authorised for the resource (e.g. cross-user arm).
    case forbidden
    /// 404. Resource not found.
    case notFound
    /// 410. Pairing code expired / device deregistered.
    case gone
    /// 429. Rate limit hit, or anti-enumeration "consumed pairing".
    case rateLimited
    /// Transport-layer error (URLSession failure).
    case network
    /// Any 5xx, with optional structured error code.
    case server(statusCode: Int, errorCode: String?)
    /// Body did not decode to the expected type.
    case decode
    /// 400 with `error: "clock_skew"` from `/api/devices/scan-result`.
    case clockSkew
    /// 401 with `error: "invalid_nonce"` from `/api/devices/scan-result`.
    case invalidNonce
}

/// Optional structured error envelope emitted by some endpoints; matches
/// `{"error": "<code>"}`.
public struct APIErrorEnvelope: Codable, Sendable, Equatable {
    public let error: String

    public init(error: String) {
        self.error = error
    }
}
