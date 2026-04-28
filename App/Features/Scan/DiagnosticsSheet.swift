//
//  DiagnosticsSheet.swift
//  ExpresScan
//
//  Hidden gear-meets-developer sheet surfaced from the home screen's
//  status pill (long-press) and the Settings sheet's "Diagnostics"
//  row. Lets QA verify that the heartbeat is live, that the SSE has
//  reconnected at least once, that the push token is registered, and
//  that a "Test scan" round-trip works without a real card.
//
//  Spec: `50-ios.md` § "Diagnostics sheet (tap connection pill)"
//

import SwiftUI
import UIKit
import UserNotifications

import AuthCore
import Networking

public struct DiagnosticsSheet: View {

    @Environment(\.app) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(RootCoordinator.self) private var coordinator

    @State private var pushTokenStatus: UNAuthorizationStatus = .notDetermined
    @State private var deviceId: String? = nil
    @State private var copyToast: String? = nil
    @State private var testScanInFlight: Bool = false
    /// Account info loaded from `GET /api/devices/me`. Lives here
    /// rather than in `SettingsViewModel` because the UI it backs
    /// (Diagnostics → Account section) lives in this sheet.
    @State private var accountInfo: AccountInfo? = nil
    @State private var accountLoading: Bool = false
    @State private var accountError: String? = nil

    /// Trimmed view-model for the Account section. Mirrors the
    /// `DeviceMeResponse` shape returned by `GET /api/devices/me`.
    private struct AccountInfo: Sendable {
        /// Server-side resolved label (priority: name → email → user
        /// id). The view falls back to `name`/`email`/`userId` only
        /// for older server builds that don't ship `ownerDisplayName`.
        let displayName: String?
        /// `users.name` from BetterAuth (may be null).
        let name: String?
        /// `users.email` from BetterAuth (may be null on
        /// auto-provisioned rows).
        let email: String?
        let userId: String?
        let registeredAtIso: String?
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                connectionSection
                deviceSection
                accountSection
                testSection
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .expressBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadDiagnostics()
                await loadAccount()
            }
            .overlay(alignment: .bottom) {
                if let copyToast {
                    Text(copyToast)
                        .font(.callout)
                        .padding(Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .padding(.bottom, Spacing.lg)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var connectionSection: some View {
        Section("Connection") {
            if let scan = coordinator.scan {
                let status = coordinator.deviceState?.connectionStatus ?? scan.connectionStatus
                let lastSync = coordinator.deviceState?.lastHeartbeatAt ?? scan.lastHeartbeatAt
                let reconnects = coordinator.deviceState?.reconnectCount ?? scan.reconnectCount
                LabeledContent("Status", value: connectionLabel(status))
                LabeledContent("Reconnects", value: "\(reconnects)")
                LabeledContent(
                    "Last sync",
                    value: lastSync.map { Self.relative(from: $0) } ?? "—"
                )
                LabeledContent("Pending uploads", value: "\(scan.pendingScanResultCount)")
            } else {
                Text("No active session.").foregroundStyle(.secondary)
            }
        }
    }

    private var deviceSection: some View {
        Section("Device") {
            LabeledContent("Push permission", value: pushTokenStatus.diagnosticLabel)
            LabeledContent("APNs environment", value: BuildConfig.apnsEnvironment)
            CopyableValueRow(
                "Server",
                value: app.api.baseURL.absoluteString,
                onCopy: { _ in showToast("Server URL copied") }
            )
            CopyableValueRow(
                "Device ID",
                value: deviceId,
                onCopy: { _ in showToast("Device ID copied") }
            )
            LabeledContent("Build", value: BuildConfig.appVersion)
        }
    }

    /// Account info that used to live on the Settings page. Moved
    /// here so Settings stays focused on user-mutable state — account
    /// metadata is read-only context that QA / support need at hand.
    @ViewBuilder
    private var accountSection: some View {
        Section("Account") {
            if let me = accountInfo {
                // Priority: name → email → user id (matches the
                // server's `ownerDisplayName` resolver). The server
                // already collapses these in `ownerDisplayName`; we
                // re-derive locally only as a defense for older
                // server builds that don't yet ship the field.
                let label = me.displayName
                    ?? me.name
                    ?? me.email
                    ?? me.userId
                    ?? "—"
                LabeledContent("Signed in as", value: label)
                if let email = me.email, email != label {
                    LabeledContent("Email", value: email)
                }
                if let registered = me.registeredAtIso {
                    LabeledContent("Registered", value: Self.formattedRegistered(registered))
                }
            } else if accountLoading {
                HStack { ProgressView().controlSize(.small); Text("Loading…") }
            } else if let err = accountError {
                Text(err).font(.caption).foregroundStyle(.secondary)
                Button("Retry") { Task { await loadAccount() } }
            } else {
                LabeledContent("Signed in as", value: "—")
            }
        }
    }

    private var testSection: some View {
        Section("Test") {
            Button {
                Task { await runTestScan() }
            } label: {
                HStack {
                    if testScanInFlight {
                        ProgressView()
                    }
                    Text("Run test sync")
                }
            }
            .disabled(testScanInFlight)
            Text("Forces an immediate device-state sync so QA can confirm bearer auth + connectivity without holding a card.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func connectionLabel(_ status: ConnectionStatus) -> String {
        switch status {
        case .offline: return "Offline"
        case .connecting: return "Connecting"
        case .online: return "Online"
        case .reconnecting: return "Reconnecting"
        }
    }

    private static func relative(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func loadDiagnostics() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            self.pushTokenStatus = settings.authorizationStatus
        }
        let deviceId = (try? await app.authStore.loadDeviceID()) ?? nil
        await MainActor.run {
            self.deviceId = deviceId
        }
    }

    /// Calls `GET /api/devices/me` and populates the Account section.
    /// Mirrors the SettingsViewModel.refreshAccount logic so the row
    /// renders the same display-name / userId / registered triple
    /// that used to live on the Settings page.
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

    private func runTestScan() async {
        testScanInFlight = true
        defer { testScanInFlight = false }

        // The `/heartbeat` endpoint was retired in slice C — sync via
        // the consolidated `/me/state/sync` route instead.
        guard let dsc = coordinator.deviceState else {
            showToast("No active session")
            return
        }
        let ok = await dsc.syncOnce()
        showToast(ok ? "Sync OK" : "Sync failed")
    }

    private func showToast(_ message: String) {
        copyToast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                if copyToast == message { copyToast = nil }
            }
        }
    }
}

// MARK: - Local helpers

private extension UNAuthorizationStatus {
    var diagnosticLabel: String {
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
