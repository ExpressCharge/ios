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
import Models

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
