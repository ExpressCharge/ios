//
//  ScanResultSigner.swift
//  Crypto
//
//  Signs the `nonce` field that accompanies `POST /api/devices/scan-result`.
//
//  Spec: `60-security.md` § 6 and `20-contracts.md` § "Endpoint detail:
//  POST /api/devices/scan-result". The `"scan-result/v1|"` prefix is
//  required for domain separation; the `deviceSecret` MUST NOT be reused
//  for any other HMAC purpose.
//

import CryptoKit
import Foundation

/// Errors thrown by `ScanResultSigner`'s initializer.
public enum ScanResultSignerError: Error, Equatable, Sendable {
    /// The supplied string was not valid base64url.
    case invalidBase64URL
    /// The decoded key was empty (sentinel against an accidental `""`).
    case emptyKey
}

/// HMAC-SHA256 signer for scan-result nonces.
public struct ScanResultSigner: Sendable {
    /// Raw key, base64url-decoded from the server-issued `deviceSecret`.
    public let secret: SymmetricKey

    /// Initialises the signer from the base64url-encoded `deviceSecret`
    /// returned by `POST /api/devices/register`.
    public init(deviceSecretBase64URL: String) throws {
        guard let raw = Base64URL.decode(deviceSecretBase64URL) else {
            throw ScanResultSignerError.invalidBase64URL
        }
        guard !raw.isEmpty else {
            throw ScanResultSignerError.emptyKey
        }
        self.secret = SymmetricKey(data: raw)
    }

    /// Signs `"scan-result/v1|{idTag}|{pairingCode}|{deviceId}|{ts}"` with
    /// HMAC-SHA256 using the device secret. Returns lowercase hex.
    public func sign(
        idTag: String,
        pairingCode: String,
        deviceId: String,
        ts: Int64
    ) -> String {
        let message = "scan-result/v1|\(idTag)|\(pairingCode)|\(deviceId)|\(ts)"
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(message.utf8),
            using: secret
        )
        return Data(mac).hexLowercased
    }
}
