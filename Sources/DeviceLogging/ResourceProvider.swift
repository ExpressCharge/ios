//
//  ResourceProvider.swift
//  DeviceLogging
//
//  Builds the OTel `resource` block that's identical for every record
//  emitted by a given process boot. Mirrors OTel's `service.*` and
//  `os.*` semantic conventions so that — when we eventually migrate to
//  Loki / VictoriaLogs — these become the natural label keys.
//
//  Kept dependency-free (Foundation only) so this module stays under
//  the SwiftPM banned-imports rule (no UIKit / SwiftUI / CoreNFC /
//  UserNotifications / WatchKit / AppKit). The app target injects the
//  `device.id` (already in keychain) and `service.version` (from
//  `BuildConfig`) at bootstrap time — neither of which `Sources/` can
//  reach for itself.
//

import Foundation

/// Build helper for `OTelLogRecord.resource`. Stateless; the bootstrap
/// caller picks values appropriate for the target (iOS app, future
/// macOS host process, etc.) and passes them in.
public enum ResourceProvider {

    /// Construct a resource block with the standard set of keys. Pass
    /// `nil` for keys that aren't applicable on this target — they're
    /// dropped from the dict.
    public static func build(
        serviceName: String,
        serviceVersion: String,
        deviceId: String?,
        osName: String,
        osVersion: String
    ) -> [String: String] {
        var dict: [String: String] = [
            "service.name": serviceName,
            "service.version": serviceVersion,
            "os.name": osName,
            "os.version": osVersion,
        ]
        if let deviceId, !deviceId.isEmpty {
            dict["device.id"] = deviceId
        }
        return dict
    }
}
