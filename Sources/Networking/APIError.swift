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
public enum APIError: Error, Sendable {
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
    /// Transport-layer error (URLSession failure). `detail` carries the
    /// raw `URLError.code` + `localizedDescription` for admin-only
    /// diagnostics; ignored by `Equatable`.
    case network(detail: String? = nil)
    /// Any 5xx, with optional structured error code.
    case server(statusCode: Int, errorCode: String?)
    /// Body did not decode to the expected type. `detail` carries the
    /// underlying `DecodingError` description for admin-only
    /// diagnostics; ignored by `Equatable`.
    case decode(detail: String? = nil)
    /// 400 with `error: "clock_skew"` from `/api/devices/scan-result`.
    case clockSkew
    /// 401 with `error: "invalid_nonce"` from `/api/devices/scan-result`.
    case invalidNonce
}

// MARK: - Equatable (detail-ignoring)

extension APIError: Equatable {
    public static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized),
            (.forbidden, .forbidden),
            (.notFound, .notFound),
            (.gone, .gone),
            (.rateLimited, .rateLimited),
            (.clockSkew, .clockSkew),
            (.invalidNonce, .invalidNonce):
            return true
        case (.network, .network):
            // `detail` is diagnostic noise — two transport failures are
            // considered equal regardless of the underlying URLError.
            return true
        case (.decode, .decode):
            // Same: `detail` carries DecodingError description for admin
            // surfacing only.
            return true
        case (.server(let lc, let le), .server(let rc, let re)):
            return lc == rc && le == re
        default:
            return false
        }
    }
}

// MARK: - Diagnostics

extension APIError {
    /// Non-localised, admin-only diagnostic string. Carries the HTTP
    /// status, error code, and any structured detail. Customer-facing
    /// copy lives in `CustomerFacingMessage` — never surface this in
    /// the customer flow.
    public var diagnosticDescription: String {
        switch self {
        case .unauthorized:
            return "HTTP 401 unauthorized"
        case .forbidden:
            return "HTTP 403 forbidden"
        case .notFound:
            return "HTTP 404 not_found"
        case .gone:
            return "HTTP 410 gone"
        case .rateLimited:
            return "HTTP 429 rate_limited"
        case .network(let detail):
            return detail.map { "Network: \($0)" } ?? "Network error"
        case .server(let code, let errorCode):
            if let errorCode {
                return "HTTP \(code) \(errorCode)"
            }
            return "HTTP \(code)"
        case .decode(let detail):
            return detail.map { "Decode: \($0)" } ?? "Decode error"
        case .clockSkew:
            return "HTTP 400 clock_skew"
        case .invalidNonce:
            return "HTTP 401 invalid_nonce"
        }
    }
}

/// Optional structured error envelope emitted by some endpoints; matches
/// `{"error": "<code>"}`.
public struct APIErrorEnvelope: Codable, Sendable, Equatable {
    public let error: String

    public init(error: String) {
        self.error = error
    }
}
