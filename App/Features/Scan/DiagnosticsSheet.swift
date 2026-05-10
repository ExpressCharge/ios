//
//  DiagnosticsSheet.swift
//  ExpresScan
//
//  Admin-only diagnostics surface, redesigned for visual consistency
//  with the rest of the app: card-grouped scroll view, no system
//  `Form`. Reachable from the redesigned Settings page's
//  `DiagnosticsLinkCard` (which is omitted in customer mode), so this
//  view never sees a customer account.
//
//  Every row + behavior from the original sheet is preserved:
//  Connection status, Device IDs, Account info, "Run test sync"
//  button, and the copy-to-clipboard toast.
//
//  Spec: `50-ios.md` § "Diagnostics sheet (tap connection pill)"
//

import AuthCore
import DeviceLogging
import Networking
import SwiftUI
import UIKit
import UserNotifications

public struct DiagnosticsSheet: View {

    @Environment(\.app) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(RootCoordinator.self) private var coordinator

    @State private var pushTokenStatus: UNAuthorizationStatus = .notDetermined
    @State private var deviceId: String? = nil
    @State private var copyToast: String? = nil
    @State private var testScanInFlight: Bool = false
    @State private var accountInfo: AccountInfo? = nil
    @State private var accountLoading: Bool = false
    @State private var accountError: String? = nil
    @State private var recentLogs: [OTelLogRecord] = []

    /// Trimmed view-model for the Account section. Mirrors the
    /// `DeviceMeResponse` shape returned by `GET /api/devices/me`.
    fileprivate struct AccountInfo: Sendable {
        let displayName: String?
        let name: String?
        let email: String?
        let userId: String?
        let registeredAtIso: String?
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                    DiagnosticsConnectionCard(coordinator: coordinator)
                    DiagnosticsDeviceCard(
                        pushTokenStatus: pushTokenStatus,
                        deviceId: deviceId,
                        serverURL: app.api.baseURL.absoluteString,
                        onCopy: showToast
                    )
                    DiagnosticsAccountCard(
                        info: accountInfo,
                        loading: accountLoading,
                        error: accountError,
                        onRetry: { Task { await loadAccount() } }
                    )
                    // Phase 3a — admin-only recent-logs view drained
                    // from the on-device JSONL ring buffer. Sheet is
                    // already admin-gated at its callsite
                    // (DiagnosticsLinkCard is hidden in customer mode);
                    // the card is here only when the drain is wired.
                    if !recentLogs.isEmpty {
                        DiagnosticsRecentLogsCard(
                            records: recentLogs,
                            onCopyAll: {
                                let text = Self.formatLogsForClipboard(recentLogs)
                                UIPasteboard.general.string = text
                                showToast("Logs copied")
                            },
                            onForceFlush: {
                                Task {
                                    await coordinator.deviceState?.syncOnce()
                                    await refreshRecentLogs()
                                }
                            }
                        )
                    }
                    DiagnosticsTestCard(
                        inFlight: testScanInFlight,
                        onRun: { Task { await runTestScan() } }
                    )
                }
                .padding(.horizontal, Spacing.base)
                .padding(.vertical, Spacing.lg)
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .expressBackground()
            .toast($copyToast)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadDiagnostics()
                await loadAccount()
                await refreshRecentLogs()
            }
            .refreshable {
                await loadDiagnostics()
                await loadAccount()
                await refreshRecentLogs()
            }
        }
    }

    // MARK: - Recent logs

    private func refreshRecentLogs() async {
        guard let drain = app.logDrain else { return }
        let records = await drain.recent(limit: 20)
        await MainActor.run { self.recentLogs = records }
    }

    /// Tab-separated lines suitable for pasting into a bug report.
    private static func formatLogsForClipboard(_ records: [OTelLogRecord]) -> String {
        records.map { record in
            let timestampSec = TimeInterval(record.timestamp) / 1_000_000_000.0
            let date = Date(timeIntervalSince1970: timestampSec)
            let iso = makeISO8601MillisFormatter().string(from: date)
            let category = stringAttribute(record, key: "category")
            return "\(iso)\t\(record.severityText)\t\(category)\t\(record.body)"
        }
        .joined(separator: "\n")
    }

    /// Pull a string-valued attribute, falling back to empty string.
    /// `attributes` is heterogeneous JSON (`AnyCodableJSON`), so we
    /// can't subscript-and-cast — pattern-match the case explicitly.
    fileprivate static func stringAttribute(
        _ record: OTelLogRecord, key: String
    ) -> String {
        if case .string(let s) = record.attributes[key] { return s }
        return ""
    }

    // MARK: - Helpers

    private func showToast(_ message: String) {
        copyToast = message
    }

    private func loadDiagnostics() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            self.pushTokenStatus = settings.authorizationStatus
        }
        let id = (try? await app.authStore.loadDeviceID()) ?? nil
        await MainActor.run {
            self.deviceId = id
        }
    }

    /// Calls `GET /api/devices/me` and populates the Account card.
    private func loadAccount() async {
        accountLoading = true
        accountError = nil
        defer { accountLoading = false }
        let endpoint = Endpoint(path: "/api/devices/me", method: .get)
        do {
            let me: DeviceMeResponse = try await app.api.request(endpoint)
            accountInfo = AccountInfo(
                displayName: me.ownerDisplayName,
                name: me.ownerName,
                email: me.ownerEmail,
                userId: me.ownerUserId,
                registeredAtIso: me.registeredAtIso
            )
        } catch {
            accountError = "Couldn't load account."
        }
    }

    private func runTestScan() async {
        testScanInFlight = true
        defer { testScanInFlight = false }
        guard let dsc = coordinator.deviceState else {
            showToast("No active session")
            return
        }
        let ok = await dsc.syncOnce()
        showToast(ok ? "Sync OK" : "Sync failed")
    }
}

// MARK: - DiagnosticsRecentLogsCard

private struct DiagnosticsRecentLogsCard: View {

    let records: [OTelLogRecord]
    let onCopyAll: () -> Void
    let onForceFlush: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                SectionHeader("Recent logs")
                Spacer(minLength: 0)
                Button(action: onForceFlush) {
                    Image(systemName: "arrow.up.circle")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Force flush now")
                Button(action: onCopyAll) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy logs")
            }
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                        DiagnosticsLogRow(record: record)
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .cardSurface()
    }
}

private struct DiagnosticsLogRow: View {

    let record: OTelLogRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(timeText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(ColorPalette.mutedForeground)
                Text(record.severityText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(severityColor)
                let category = DiagnosticsSheet.stringAttribute(record, key: "category")
                if !category.isEmpty {
                    Text(category)
                        .font(.caption2.monospaced())
                        .foregroundStyle(ColorPalette.mutedForeground)
                }
            }
            Text(record.body)
                .font(.caption.monospaced())
                .foregroundStyle(ColorPalette.foreground)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var timeText: String {
        let timestampSec = TimeInterval(record.timestamp) / 1_000_000_000.0
        let date = Date(timeIntervalSince1970: timestampSec)
        return DiagnosticsLogRow.timeFormatter.string(from: date)
    }

    private var severityColor: Color {
        switch LogLevel.from(severityText: record.severityText) {
        case .trace, .debug: return ColorPalette.mutedForeground
        case .info, .notice: return ColorPalette.info
        case .warning: return ColorPalette.warningAmber
        case .error, .critical: return ColorPalette.destructiveRose
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}

/// Build a fresh ISO-8601-with-ms formatter. `ISO8601DateFormatter`
/// isn't `Sendable`, so a `static let` cache violates Swift 6 strict
/// concurrency; the formatter is cheap to construct (microseconds), so
/// we just build one per call. Callers are off the hot path.
private func makeISO8601MillisFormatter() -> ISO8601DateFormatter {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}

// MARK: - Cards

private struct DiagnosticsConnectionCard: View {
    let coordinator: RootCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("Connection") {
                if let scan = coordinator.scan {
                    let status =
                        coordinator.deviceState?.connectionStatus
                        ?? scan.connectionStatus
                    StatusPill(
                        label: status.diagnosticsLabel,
                        systemImage: status.diagnosticsIcon,
                        tone: status.diagnosticsTone
                    )
                }
            }
            if let scan = coordinator.scan {
                let lastSync =
                    coordinator.deviceState?.lastHeartbeatAt
                    ?? scan.lastHeartbeatAt
                let reconnects =
                    coordinator.deviceState?.reconnectCount
                    ?? scan.reconnectCount
                LabeledContent("Reconnects") {
                    Text("\(reconnects)")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Last sync") {
                    Text(lastSync.map(Self.relative) ?? "—")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Pending uploads") {
                    Text("\(scan.pendingScanResultCount)")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No active session.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct DiagnosticsDeviceCard: View {
    let pushTokenStatus: UNAuthorizationStatus
    let deviceId: String?
    let serverURL: String
    let onCopy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("Device")
            LabeledContent("Push permission") {
                Text(pushTokenStatus.diagnosticLabel)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("APNs environment") {
                Text(BuildConfig.apnsEnvironment)
                    .foregroundStyle(.secondary)
            }
            CopyableValueRow(
                "Server",
                value: serverURL,
                onCopy: { _ in onCopy("Server URL copied") }
            )
            CopyableValueRow(
                "Device ID",
                value: deviceId,
                onCopy: { _ in onCopy("Device ID copied") }
            )
            LabeledContent("Build") {
                Text(BuildConfig.appVersion)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

private struct DiagnosticsAccountCard: View {
    let info: DiagnosticsSheet.AccountInfo?
    let loading: Bool
    let error: String?
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("Account")
            if let me = info {
                let label =
                    me.displayName
                    ?? me.name
                    ?? me.email
                    ?? me.userId
                    ?? "—"
                LabeledContent("Signed in as") {
                    Text(label)
                        .foregroundStyle(.secondary)
                }
                if let email = me.email, email != label {
                    LabeledContent("Email") {
                        Text(email)
                            .foregroundStyle(.secondary)
                    }
                }
                if let userId = me.userId {
                    LabeledContent("User ID") {
                        Text(userId)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                if let registered = me.registeredAtIso {
                    LabeledContent("Registered") {
                        Text(Self.formattedRegistered(registered))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if loading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading…")
                        .foregroundStyle(.secondary)
                }
            } else if let err = error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
            } else {
                LabeledContent("Signed in as") {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private static func formattedRegistered(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return iso }
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        return display.string(from: date)
    }
}

private struct DiagnosticsTestCard: View {
    let inFlight: Bool
    let onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("Test")
            PrimaryButton(
                "Run test sync",
                systemImage: "arrow.triangle.2.circlepath",
                state: inFlight ? .loading : .default,
                action: onRun
            )
            Text(
                "Forces an immediate device-state sync so QA can confirm bearer auth + connectivity without holding a card."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

// MARK: - ConnectionStatus pill mapping (Diagnostics)

extension ConnectionStatus {
    fileprivate var diagnosticsLabel: String {
        switch self {
        case .offline: return "Offline"
        case .connecting: return "Connecting"
        case .online: return "Online"
        case .reconnecting: return "Reconnecting"
        }
    }
    fileprivate var diagnosticsIcon: String {
        switch self {
        case .offline: return "wifi.slash"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .online: return "checkmark.circle.fill"
        case .reconnecting: return "arrow.triangle.2.circlepath.circle"
        }
    }
    fileprivate var diagnosticsTone: StatusPill.Tone {
        switch self {
        case .offline: return .negative
        case .connecting: return .info
        case .online: return .positive
        case .reconnecting: return .warning
        }
    }
}

// MARK: - UN auth-status helpers

extension UNAuthorizationStatus {
    fileprivate var diagnosticLabel: String {
        switch self {
        case .authorized: return "Authorized"
        case .denied: return "Denied"
        case .notDetermined: return "Not asked"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }
}
