//
//  DeviceRegistration.swift
//  Models
//
//  Request + response for `POST /api/devices/register`. See
//  `20-contracts.md` § "Endpoint detail: POST /api/devices/register".
//

import Foundation

/// Request body for `POST /api/devices/register`.
///
/// Sent with the `ev_billing_session` cookie from the post-Universal-Link
/// callback. The `oneTimeCode` was emitted by the web register page after
/// PKCE challenge; `codeVerifier` proves we own the original challenge.
public struct DeviceRegistrationRequest: Codable, Sendable, Equatable {
    /// One-time code received via the Universal Link, ≤60 s old.
    public let oneTimeCode: String
    /// PKCE verifier matching the challenge sent in the web flow.
    public let codeVerifier: String
    public let label: String
    /// Currently always `"ios"`.
    public let platform: String
    public let model: String
    public let osVersion: String
    public let appVersion: String
    /// Raw APNs token, base64-encoded.
    public let pushToken: String
    public let apnsEnvironment: ApnsEnvironment
    public let requestedCapabilities: [DeviceCapability]

    public init(
        oneTimeCode: String,
        codeVerifier: String,
        label: String,
        platform: String,
        model: String,
        osVersion: String,
        appVersion: String,
        pushToken: String,
        apnsEnvironment: ApnsEnvironment,
        requestedCapabilities: [DeviceCapability]
    ) {
        self.oneTimeCode = oneTimeCode
        self.codeVerifier = codeVerifier
        self.label = label
        self.platform = platform
        self.model = model
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.pushToken = pushToken
        self.apnsEnvironment = apnsEnvironment
        self.requestedCapabilities = requestedCapabilities
    }
}

/// Successful response body for `POST /api/devices/register`.
///
/// `deviceToken` and `deviceSecret` are returned ONLY in this response body,
/// never echoed elsewhere (see `60-security.md` § 1).
public struct DeviceRegistrationResponse: Codable, Sendable, Equatable {
    public let ok: Bool
    public let deviceId: String
    /// `dev_<32 random bytes base64url>` — bearer token.
    public let deviceToken: String
    /// 32 random bytes, base64url-encoded. Used as HMAC key.
    public let deviceSecret: String
    public let capabilities: [DeviceCapability]
    public let expiresAtIso: String

    public init(
        ok: Bool,
        deviceId: String,
        deviceToken: String,
        deviceSecret: String,
        capabilities: [DeviceCapability],
        expiresAtIso: String
    ) {
        self.ok = ok
        self.deviceId = deviceId
        self.deviceToken = deviceToken
        self.deviceSecret = deviceSecret
        self.capabilities = capabilities
        self.expiresAtIso = expiresAtIso
    }
}
