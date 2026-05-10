//
//  SyncRequest.swift
//  DeviceSync
//
//  Body of `POST /api/devices/me/state/sync`. Mirrors the
//  `SyncRequest` TypeScript shape in the plan's "Sync envelope" section.
//
//  Wave 6.1 (post-merge) — diagnostics widened so the web admin can
//  remotely diagnose every device, especially kiosks (which have no
//  visible local UI). New fields are optional in the server zod schema
//  so older clients keep round-tripping cleanly while the field
//  inventory grows.
//

import DeviceLogging
import Foundation
import Models

public struct SyncRequest: Sendable, Equatable, Codable {

    /// Settings the client has touched locally and wants merged. Server
    /// applies LWW per `key` against its own row (clamping `updatedAt`
    /// to ≤ now+5s).
    public var pendingSettings: [PendingSetting]
    public var diagnostics: Diagnostics

    /// OpenTelemetry-shaped log records drained from the device's local
    /// ring buffer. Capped at 100 records per sync (Phase 3c). Older
    /// servers ignore the field; newer servers bulk-insert with
    /// `INSERT … ON CONFLICT (device_id, seq) DO NOTHING`.
    public var logs: [OTelLogRecord]?

    /// Highest `expresscharge.seq` (UInt64-as-string) included in `logs`.
    /// Server's response `logs.ackedSeq` confirms the high-water mark
    /// the client should advance past. Encoded as string to avoid JS
    /// Number precision loss; `LogDrain.acknowledge` parses it back.
    public var logCursor: String?

    public init(
        pendingSettings: [PendingSetting],
        diagnostics: Diagnostics,
        logs: [OTelLogRecord]? = nil,
        logCursor: String? = nil
    ) {
        self.pendingSettings = pendingSettings
        self.diagnostics = diagnostics
        self.logs = logs
        self.logCursor = logCursor
    }

    public struct PendingSetting: Sendable, Equatable, Codable {
        public var key: String
        public var value: AnyCodableJSON
        public var updatedAt: String  // ISO-8601 string (server clamps)

        public init(key: String, value: AnyCodableJSON, updatedAt: String) {
            self.key = key
            self.value = value
            self.updatedAt = updatedAt
        }
    }

    /// Comprehensive diagnostics blob. Every field is optional from the
    /// server's perspective except the original Wave-6 set — older
    /// clients stay green. The new fields land directly in
    /// `devices.last_status` JSONB and are surfaced on the web detail
    /// page.
    public struct Diagnostics: Sendable, Equatable, Codable {
        // ---- Core (required) -------------------------------------
        public var appVersion: String
        public var osVersion: String
        public var model: String
        public var pushPermission: PushPermission
        public var nfcAvailable: Bool
        public var pendingUploads: Int
        public var reconnectCount: Int

        // ---- Identity / locale -----------------------------------
        /// `iOS` / `iPadOS` / `macOS` per `UIDevice.systemName`.
        public var platform: String?
        /// User-visible model name e.g. `iPhone 15 Pro`. The base
        /// `model` field is the generic `iPhone` / `iPad` string.
        public var localizedModel: String?
        /// `Locale.current.identifier`.
        public var locale: String?
        /// `TimeZone.current.identifier`.
        public var timezone: String?
        /// `BuildConfig.apnsEnvironment` — sandbox / production. So the
        /// admin can spot a TestFlight build talking to the wrong APNs.
        public var apnsEnvironment: String?
        /// Last 8 of the APNs device token if registered. `nil` when
        /// the device hasn't received an APNs token (permission asked
        /// but no token, or push not registered yet). The web UI uses
        /// this to render the distinct "Notifications on but no APNS
        /// key" sub-state without us having to denormalize.
        public var pushTokenLast8: String?

        // ---- Permissions (granular) ------------------------------
        /// NFC reader access permission, if applicable. `nil` on a
        /// device without an NFC reader (laptops/tablets).
        public var nfcPermission: PermissionState?
        /// Background app refresh status — relevant for kiosks that
        /// rely on background sync continuity.
        public var backgroundRefreshStatus: BackgroundRefreshState?
        /// Local network permission (Bonjour / discovery). Optional,
        /// not all builds query it.
        public var localNetworkPermission: PermissionState?

        // ---- Health (battery + thermals) -------------------------
        /// 0.0 – 1.0, `nil` when monitoring is disabled.
        public var batteryLevel: Double?
        /// `unplugged` / `charging` / `full` / `unknown`.
        public var batteryState: BatteryState?
        public var lowPowerMode: Bool?
        public var thermalState: ThermalState?

        // ---- Network --------------------------------------------
        /// `wifi` / `cellular` / `wired` / `loopback` / `unknown`.
        public var networkInterface: String?
        public var networkIsConstrained: Bool?
        public var networkIsExpensive: Bool?

        // ---- Storage --------------------------------------------
        /// Bytes free on the volume containing Application Support.
        public var diskFreeBytes: Int64?

        public enum PushPermission: String, Sendable, Equatable, Codable {
            case authorized
            case denied
            case notDetermined
            case provisional
            case ephemeral
        }

        public enum PermissionState: String, Sendable, Equatable, Codable {
            case authorized
            case denied
            case notDetermined
            case restricted
            case unavailable
        }

        public enum BackgroundRefreshState: String, Sendable, Equatable, Codable {
            case available
            case denied
            case restricted
        }

        public enum BatteryState: String, Sendable, Equatable, Codable {
            case unknown
            case unplugged
            case charging
            case full
        }

        public enum ThermalState: String, Sendable, Equatable, Codable {
            case nominal
            case fair
            case serious
            case critical
        }

        public init(
            appVersion: String,
            osVersion: String,
            model: String,
            pushPermission: PushPermission,
            nfcAvailable: Bool,
            pendingUploads: Int,
            reconnectCount: Int,
            platform: String? = nil,
            localizedModel: String? = nil,
            locale: String? = nil,
            timezone: String? = nil,
            apnsEnvironment: String? = nil,
            pushTokenLast8: String? = nil,
            nfcPermission: PermissionState? = nil,
            backgroundRefreshStatus: BackgroundRefreshState? = nil,
            localNetworkPermission: PermissionState? = nil,
            batteryLevel: Double? = nil,
            batteryState: BatteryState? = nil,
            lowPowerMode: Bool? = nil,
            thermalState: ThermalState? = nil,
            networkInterface: String? = nil,
            networkIsConstrained: Bool? = nil,
            networkIsExpensive: Bool? = nil,
            diskFreeBytes: Int64? = nil
        ) {
            self.appVersion = appVersion
            self.osVersion = osVersion
            self.model = model
            self.pushPermission = pushPermission
            self.nfcAvailable = nfcAvailable
            self.pendingUploads = pendingUploads
            self.reconnectCount = reconnectCount
            self.platform = platform
            self.localizedModel = localizedModel
            self.locale = locale
            self.timezone = timezone
            self.apnsEnvironment = apnsEnvironment
            self.pushTokenLast8 = pushTokenLast8
            self.nfcPermission = nfcPermission
            self.backgroundRefreshStatus = backgroundRefreshStatus
            self.localNetworkPermission = localNetworkPermission
            self.batteryLevel = batteryLevel
            self.batteryState = batteryState
            self.lowPowerMode = lowPowerMode
            self.thermalState = thermalState
            self.networkInterface = networkInterface
            self.networkIsConstrained = networkIsConstrained
            self.networkIsExpensive = networkIsExpensive
            self.diskFreeBytes = diskFreeBytes
        }

        /// Returns a copy with the customer-restricted device-health
        /// fields cleared. Track I6 — customer accounts shouldn't ship
        /// us battery / thermal state / disk free / low power mode;
        /// only Polaris-team (admin-owned) devices keep the full
        /// readout for fleet diagnosis.
        public func scrubbedForCustomerAccount() -> Diagnostics {
            var copy = self
            copy.batteryLevel = nil
            copy.batteryState = nil
            copy.lowPowerMode = nil
            copy.thermalState = nil
            copy.diskFreeBytes = nil
            return copy
        }
    }
}
