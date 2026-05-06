//
//  DeviceSettingValue.swift
//  DeviceSync
//
//  Per-key device-settings value with last-write-wins metadata. Mirrors
//  the backend `device_settings (key, valueJson, updatedAt, updatedBy)`
//  rows.
//
//  The `value` field is heterogeneous JSON (string for `device.label`,
//  bool for `notifications.scanRequest`, future keys may be numbers /
//  arrays / objects). We wrap arbitrary JSON in a small `AnyCodableJSON`
//  to keep the type `Sendable` + `Codable` without losing fidelity.
//

import Foundation

// MARK: - AnyCodableJSON

/// A type-erased JSON value. Holds a concrete enum case for each of the
/// JSON primitives plus container types. Round-trips losslessly through
/// `JSONEncoder` / `JSONDecoder`.
public enum AnyCodableJSON: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([AnyCodableJSON])
    case object([String: AnyCodableJSON])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
            return
        }
        if let b = try? c.decode(Bool.self) {
            self = .bool(b)
            return
        }
        if let i = try? c.decode(Int64.self) {
            self = .int(i)
            return
        }
        if let d = try? c.decode(Double.self) {
            self = .double(d)
            return
        }
        if let s = try? c.decode(String.self) {
            self = .string(s)
            return
        }
        if let arr = try? c.decode([AnyCodableJSON].self) {
            self = .array(arr)
            return
        }
        if let obj = try? c.decode([String: AnyCodableJSON].self) {
            self = .object(obj)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: c,
            debugDescription: "AnyCodableJSON: unsupported JSON value"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

// MARK: - DeviceSettingValue

/// One row in the per-device settings map. Carries the value plus the
/// LWW metadata (`updatedAt`, `updatedBy`) needed to merge against the
/// server.
public struct DeviceSettingValue: Sendable, Equatable, Codable {
    public var value: AnyCodableJSON
    public var updatedAt: Date
    public var updatedBy: String

    public init(value: AnyCodableJSON, updatedAt: Date, updatedBy: String) {
        self.value = value
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
    }
}
