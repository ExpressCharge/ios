//
//  AnyCodableJSON.swift
//  Models
//
//  A type-erased JSON value used by every wire shape that carries
//  arbitrary structured data — `DeviceSettingValue`, `LogEntry.fields`,
//  etc. Lives in `Models` so it has no other module dependencies and
//  every consumer can reach it without a cycle.
//

import Foundation

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
