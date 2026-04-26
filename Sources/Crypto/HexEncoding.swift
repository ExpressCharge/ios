//
//  HexEncoding.swift
//  Crypto
//
//  Tiny, allocation-light hex helpers. The HMAC signer returns lowercase
//  hex; the NFC layer (in `App/`) emits uppercase hex for `idTag`. Keeping
//  both helpers here means there is exactly one place that defines the
//  alphabet.
//

import Foundation

extension Data {
    /// Lowercase hex string. No separators.
    public var hexLowercased: String {
        let alphabet: [UInt8] = Array("0123456789abcdef".utf8)
        return hexString(alphabet: alphabet)
    }

    /// Uppercase hex string. No separators. Matches the backend's
    /// `steveOcppIdTag` format.
    public var hexUppercased: String {
        let alphabet: [UInt8] = Array("0123456789ABCDEF".utf8)
        return hexString(alphabet: alphabet)
    }

    /// Decodes a hex string (case-insensitive, no separators) into bytes.
    /// Returns `nil` if the input has odd length or contains non-hex chars.
    public init?(hexEncoded string: String) {
        let utf8 = Array(string.utf8)
        guard utf8.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(utf8.count / 2)
        var i = 0
        while i < utf8.count {
            guard
                let hi = Self.nibble(utf8[i]),
                let lo = Self.nibble(utf8[i + 1])
            else { return nil }
            bytes.append((hi << 4) | lo)
            i += 2
        }
        self = Data(bytes)
    }

    // MARK: - Internals

    private func hexString(alphabet: [UInt8]) -> String {
        var out = [UInt8]()
        out.reserveCapacity(self.count * 2)
        for byte in self {
            out.append(alphabet[Int(byte >> 4)])
            out.append(alphabet[Int(byte & 0x0F)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func nibble(_ ascii: UInt8) -> UInt8? {
        switch ascii {
        case 0x30...0x39: return ascii - 0x30                  // '0'-'9'
        case 0x41...0x46: return ascii - 0x41 + 10             // 'A'-'F'
        case 0x61...0x66: return ascii - 0x61 + 10             // 'a'-'f'
        default: return nil
        }
    }
}
