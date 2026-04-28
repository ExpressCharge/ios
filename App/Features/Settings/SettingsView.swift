//
//  SettingsView.swift
//  ExpresScan
//
//  Form-style settings page. Sections:
//   - Connectivity (status pill, last sync, Diagnostics push link)
//   - Device (name, model, OS, app version)
//   - Permissions (notifications status; future: camera for QR, etc.)
//   - About (privacy policy, terms, "Open iOS Settings" link, build)
//   - Sign out (red, confirms; calls DELETE /api/devices/{id} and
//     clears Keychain)
//
//  Account (display name, device id, registered) lives inside the
//  Diagnostics sheet — see `DiagnosticsSheet.swift`.
//
//  Spec: `50-ios.md` § "Settings screen" + § "Sign-out = deregister".
//

import SwiftUI
import UIKit
import UserNotifications

import AuthCore

public struct SettingsView: View {

    @Environment(\.app) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(RootCoordinator.self) private var coordinator

    @State private var viewModel: SettingsViewModel?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isShowingSignOutConfirm: Bool = false

    public init() {}

    public var body: some View {
        // Settings is now pushed via `NavigationLink` from the toolbar
        // gear button (see `SettingsToolbarMenuButton`) — the parent
        // already owns the `NavigationStack`, so no wrapper here.
        Group {
            if let vm = viewModel {
                formContent(vm)
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .expressBackground()
        .task {
            if viewModel == nil {
                let vm = SettingsViewModel(environment: app, router: coordinator)
                self.viewModel = vm
                await vm.refreshAccount()
            }
            await refreshNotificationStatus()
        }
    }

    @ViewBuilder
    private func formContent(_ vm: SettingsViewModel) -> some View {
        @Bindable var vm = vm

        Form {
            connectivitySection
            deviceSection(vm: vm)
            permissionsSection
            aboutSection

            Section {
                Button(role: .destructive) {
                    isShowingSignOutConfirm = true
                } label: {
                    if vm.isSigningOut {
                        HStack {
                            ProgressView()
                            Text("Signing out…")
                        }
                    } else {
                        Text("Sign out")
                    }
                }
                .disabled(vm.isSigningOut)
                if let err = vm.signOutError {
                    Text(err).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog(
            "Sign out and deregister this device?",
            isPresented: $isShowingSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                Task {
                    await vm.signOut()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This iPhone will stop receiving scan requests. You'll need to sign in again to use ExpressCharge.")
        }
    }

    // MARK: - Sections

    /// New top "Connectivity" section — replaces the connection pill
    /// that used to live in `ReadyView`'s top-right. Surfaces the live
    /// connection status from the consolidated `DeviceStateCoordinator`
    /// (slice G).
    private var connectivitySection: some View {
        Section("Connectivity") {
            let status = coordinator.deviceState?.connectionStatus
                ?? coordinator.scan?.connectionStatus
                ?? .offline
            LabeledContent("Status") {
                StatusPill(
                    label: status.settingsLabel,
                    systemImage: status.settingsIcon,
                    tone: status.settingsTone
                )
            }
            // Mirrors the Diagnostics-sheet "Last sync" row so the
            // operator can see freshness without drilling in.
            let lastSync = coordinator.deviceState?.lastHeartbeatAt
                ?? coordinator.scan?.lastHeartbeatAt
            LabeledContent(
                "Last sync",
                value: lastSync.map { Self.relativeTime(from: $0) } ?? "—"
            )
            NavigationLink {
                DiagnosticsSheet()
                    .environment(coordinator)
            } label: {
                Label("Diagnostics", systemImage: "wrench.and.screwdriver")
            }
        }
    }

    private func deviceSection(vm: SettingsViewModel) -> some View {
        @Bindable var vm = vm
        return Section("Device") {
            // Inline `LabeledContent` so the row's left/right
            // alignment matches Model / iOS / App. The owner-side
            // rename endpoint isn't exposed in v1 — we persist the
            // preferred label locally and let the admin's
            // server-stored label remain authoritative.
            LabeledContent("Device Name") {
                TextField("Device name", text: $vm.label, prompt: Text(UIDevice.current.name))
                    .multilineTextAlignment(.trailing)
                    .submitLabel(.done)
                    .onSubmit { vm.commitLocalRename() }
            }
            LabeledContent("Model", value: UIDevice.current.model)
            LabeledContent("iOS", value: UIDevice.current.systemVersion)
            LabeledContent("App", value: BuildConfig.appVersion)
        }
    }

    /// Permissions the app holds (or wants). Today only Notifications;
    /// future entries (e.g., Camera for QR scanning) slot in here.
    private var permissionsSection: some View {
        Section("Permissions") {
            LabeledContent("Notifications") {
                StatusPill(
                    label: notificationStatus.label,
                    systemImage: notificationStatus.icon,
                    tone: notificationStatus.tone
                )
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Link(destination: URL(string: "https://manage.polaris.express/privacy")!) {
                Label("Privacy policy", systemImage: "hand.raised")
            }
            Link(destination: URL(string: "https://manage.polaris.express/terms")!) {
                Label("Terms of service", systemImage: "doc.text")
            }
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                // Same `Label` style as the links above so the row
                // reads as a sibling. Icon is the system-Settings gear.
                Label("Open iOS Settings", systemImage: "gear")
            }
            LabeledContent("Build", value: BuildConfig.appVersion)
        }
    }

    // MARK: - Date helpers

    private static func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Actions

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            self.notificationStatus = settings.authorizationStatus
        }
    }
}

// MARK: - ConnectionStatus pill mapping (Settings)

private extension ConnectionStatus {
    var settingsLabel: String {
        switch self {
        case .offline: return "Offline"
        case .connecting: return "Connecting"
        case .online: return "Online"
        case .reconnecting: return "Reconnecting"
        }
    }
    var settingsIcon: String {
        switch self {
        case .offline: return "wifi.slash"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .online: return "checkmark.circle.fill"
        case .reconnecting: return "arrow.triangle.2.circlepath.circle"
        }
    }
    var settingsTone: StatusPill.Tone {
        switch self {
        case .offline: return .negative
        case .connecting: return .info
        case .online: return .positive
        case .reconnecting: return .warning
        }
    }
}

// MARK: - UN auth-status helpers

private extension UNAuthorizationStatus {
    var label: String {
        switch self {
        case .notDetermined: return "Ask"
        case .denied: return "Denied"
        case .authorized: return "Allowed"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }
    var icon: String {
        switch self {
        case .authorized, .provisional: return "checkmark.circle.fill"
        case .denied: return "xmark.octagon.fill"
        case .notDetermined: return "questionmark.circle"
        case .ephemeral: return "hourglass"
        @unknown default: return "questionmark.circle"
        }
    }
    var tone: StatusPill.Tone {
        switch self {
        case .authorized, .provisional: return .positive
        case .denied: return .negative
        case .notDetermined, .ephemeral: return .warning
        @unknown default: return .neutral
        }
    }
}
