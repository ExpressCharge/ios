//
//  Base64URL.swift
//  Crypto
//
//  base64url (RFC 4648 §5) decoder. Used by `ScanResultSigner` to turn the
//  server-issued `deviceSecret` into raw key bytes.
//

import Foundation

enum Base64URL {
    /// Decode a base64url string. Optional `=` padding is accepted but not
    /// required. Returns `nil` on any non-alphabet character.
    static func decode(_ string: String) -> Data? {
        // Replace base64url alphabet with standard base64.
        var transformed = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Pad to a multiple of 4.
        let remainder = transformed.count % 4
        if remainder == 2 {
            transformed.append("==")
        } else if remainder == 3 {
            transformed.append("=")
        } else if remainder == 1 {
            // `==` is the longest legal padding; a remainder of 1 is invalid.
            return nil
        }

        return Data(base64Encoded: transformed, options: [])
    }
}
