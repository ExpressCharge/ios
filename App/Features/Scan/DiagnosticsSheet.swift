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

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                connectionSection
                deviceSection
                testSection
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadDiagnostics() }
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
                LabeledContent("Status", value: connectionLabel(scan.connectionStatus))
                LabeledContent("Reconnects", value: "\(scan.reconnectCount)")
                LabeledContent(
                    "Last heartbeat",
                    value: scan.lastHeartbeatAt.map { Self.relative(from: $0) } ?? "—"
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

    private var testSection: some View {
        Section("Test") {
            Button {
                Task { await runTestScan() }
            } label: {
                HStack {
                    if testScanInFlight {
                        ProgressView()
                    }
                    Text("Run test heartbeat")
                }
            }
            .disabled(testScanInFlight)
            Text("Sends a heartbeat to the backend so QA can confirm bearer auth + connectivity without holding a card.")
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

    private func runTestScan() async {
        testScanInFlight = true
        defer { testScanInFlight = false }

        let endpoint = Endpoint(
            path: "/api/devices/heartbeat",
            method: .post,
            requiresAuth: true
        )
        do {
            try await app.api.send(endpoint)
            showToast("Heartbeat OK")
        } catch {
            showToast("Heartbeat failed")
        }
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
