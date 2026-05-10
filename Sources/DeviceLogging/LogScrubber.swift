//
//  LogScrubber.swift
//  DeviceLogging
//
//  Defence-in-depth PII redactor. Applied by
//  `RingBufferJSONLogHandler` BEFORE every record is appended to disk
//  AND BEFORE it leaves the device via the sync envelope — never
//  bypassed.
//
//  The deny-list lives here on the iOS side; the server-side mirror at
//  `expresscharge/src/lib/utils/log_scrubber.ts` uses identical regexes.
//  Shared fixtures live under `docs/logging/scrubber-fixtures.json`
//  (Phase 3e) so both sides stay in lockstep.
//
//  WHY a regex deny-list rather than typed redaction? Most logs are
//  free-form `body` strings; we don't control every interpolation site.
//  A coarse regex pass catches the common shapes (emails, JWTs, bearer
//  tokens, card identifiers, phone numbers) without forcing every call
//  site to use structured metadata. Structured `attributes` keys whose
//  NAMES indicate sensitivity (e.g. `card_*`, `Authorization`) get
//  their VALUES wholesale-redacted.
//

import Foundation
import Models

public enum LogScrubber {

    /// Replacement when a regex matches inside a free-form string.
    public static let redactedToken = "<redacted>"

    // MARK: - Patterns
    //
    // Each pattern is tested in `LogScrubberTests` against the shared
    // `scrubber-fixtures.json` corpus. Keep these in sync with the
    // server's `log_scrubber.ts`.

    // Email — RFC-shaped local-part and domain. Conservative.
    private static let emailRegex = try! NSRegularExpression(
        pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
        options: []
    )

    // JSON Web Token — `eyJ...` three-part dotted base64url.
    private static let jwtRegex = try! NSRegularExpression(
        pattern: #"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#,
        options: []
    )

    // `Bearer <token>` — case-insensitive on `Bearer`, generous on
    // token shape (must be at least 8 chars to avoid false positives
    // on the word "Bearer" alone).
    private static let bearerRegex = try! NSRegularExpression(
        pattern: #"(?i)bearer\s+[A-Za-z0-9._\-]{8,}"#,
        options: []
    )

    // E.164 phone-number (conservative — must start with + and have
    // 7-15 digits). Domestic formats are too easy to false-positive
    // and aren't worth scrubbing in our context.
    private static let phoneRegex = try! NSRegularExpression(
        pattern: #"\+\d{7,15}\b"#,
        options: []
    )

    /// Attribute KEYS whose values should be wholesale-redacted
    /// regardless of content.
    private static let sensitiveAttributeKeys: Set<String> = [
        "authorization",
        "Authorization",
        "x-auth-token",
        "X-Auth-Token",
        "cookie",
        "Cookie",
        "set-cookie",
        "Set-Cookie",
    ]

    /// Attribute KEYS matching this prefix get wholesale-redacted.
    private static let sensitiveAttributeKeyPrefixes: [String] = [
        "card_",
    ]

    // MARK: - Public API

    /// Scrub a record in place. Mutates `body` and string-valued
    /// `attributes` (recursively for nested arrays/objects).
    /// `resource` is left intact — it should never carry PII by
    /// construction (`service.name`, `os.version`, `device.id`).
    public static func scrub(_ record: inout OTelLogRecord) {
        record.body = scrubString(record.body)

        var newAttrs: [String: AnyCodableJSON] = [:]
        newAttrs.reserveCapacity(record.attributes.count)
        for (key, value) in record.attributes {
            if shouldWholesaleRedact(key: key) {
                newAttrs[key] = .string(redactedToken)
            } else {
                newAttrs[key] = scrubValue(value)
            }
        }
        record.attributes = newAttrs
    }

    // MARK: - Internals

    /// Apply every regex to a free-form string and return the redacted
    /// result. Order matters — JWT before bearer before email
    /// because JWTs match the bearer regex.
    static func scrubString(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        var result = s as NSString
        result = applyRegex(jwtRegex, replacement: "<jwt>", on: result)
        result = applyRegex(bearerRegex, replacement: "Bearer <token>", on: result)
        result = applyRegex(emailRegex, replacement: "<email>", on: result)
        result = applyRegex(phoneRegex, replacement: "<phone>", on: result)
        return result as String
    }

    private static func applyRegex(
        _ regex: NSRegularExpression,
        replacement: String,
        on input: NSString
    ) -> NSString {
        let range = NSRange(location: 0, length: input.length)
        return regex.stringByReplacingMatches(
            in: input as String,
            options: [],
            range: range,
            withTemplate: replacement
        ) as NSString
    }

    private static func shouldWholesaleRedact(key: String) -> Bool {
        if sensitiveAttributeKeys.contains(key) { return true }
        for prefix in sensitiveAttributeKeyPrefixes {
            if key.hasPrefix(prefix) { return true }
        }
        return false
    }

    /// Recursively scrub strings inside an `AnyCodableJSON`.
    static func scrubValue(_ value: AnyCodableJSON) -> AnyCodableJSON {
        switch value {
        case .string(let s):
            return .string(scrubString(s))
        case .array(let arr):
            return .array(arr.map(scrubValue))
        case .object(let obj):
            var newObj: [String: AnyCodableJSON] = [:]
            newObj.reserveCapacity(obj.count)
            for (k, v) in obj {
                if shouldWholesaleRedact(key: k) {
                    newObj[k] = .string(redactedToken)
                } else {
                    newObj[k] = scrubValue(v)
                }
            }
            return .object(newObj)
        case .null, .bool, .int, .double:
            return value
        }
    }
}
