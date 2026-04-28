//
//  SettingsView.swift
//  ExpresScan
//
//  Form-style settings sheet. Sections:
//   - Device (label, model, OS, app version)
//   - Notifications (system permission status, deep-link to Settings)
//   - Account (Pocket ID display name when available)
//   - About (privacy policy, terms, build info)
//   - Sign out (red, confirms; calls DELETE /api/devices/{id} via
//     E-app-wire and clears Keychain)
//
//  Skeleton: layout + actions where possible. The "Sign out" network
//  call is stubbed to a Keychain wipe + return-to-welcome; E-app-wire
//  layers in the actual DELETE.
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
            notificationsSection
            accountSection(vm: vm)
            diagnosticsSection
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
            Text("This iPhone will stop receiving scan requests. You'll need to sign in again to use ExpresScan.")
        }
    }

    // MARK: - Sections

    /// New top "Connectivity" section — replaces the connection pill
    /// that used to live in `ReadyView`'s top-right. Surfaces the live
    /// connection status and pushes Diagnostics. TODO(slice-g): swap
    /// `ScanCoordinator.connectionStatus` for `DeviceStateCoordinator`.
    private var connectivitySection: some View {
        Section("Connectivity") {
            HStack {
                Text("Status")
                Spacer()
                let status = coordinator.scan?.connectionStatus ?? .offline
                StatusPill(
                    label: status.settingsLabel,
                    systemImage: status.settingsIcon,
                    tone: status.settingsTone
                )
            }
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
            // The owner-side rename endpoint isn't exposed in v1 — the
            // admin POST /api/admin/devices/{id}/rename needs a cookie
            // session. We persist the user's preferred label locally
            // and surface the limitation honestly.
            TextField("Device name", text: $vm.label, prompt: Text(UIDevice.current.name))
                .submitLabel(.done)
                .onSubmit { vm.commitLocalRename() }
            Text("Saved on this iPhone. Admins still see the label you registered with.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("Model", value: UIDevice.current.model)
            LabeledContent("iOS", value: UIDevice.current.systemVersion)
            LabeledContent("App", value: BuildConfig.appVersion)
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            HStack {
                Text("Permission")
                Spacer()
                StatusPill(
                    label: notificationStatus.label,
                    systemImage: notificationStatus.icon,
                    tone: notificationStatus.tone
                )
            }
            Button("Open iOS Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    private func accountSection(vm: SettingsViewModel) -> some View {
        Section("Account") {
            if vm.meIsLoading {
                HStack { ProgressView(); Text("Loading…") }
            } else if let me = vm.me {
                LabeledContent(
                    "Signed in as",
                    value: me.ownerDisplayName ?? me.ownerUserId ?? "—"
                )
                LabeledContent("Device ID", value: me.deviceId)
                if let registered = me.registeredAtIso {
                    LabeledContent("Registered", value: registered)
                }
            } else if let err = vm.meError {
                Text(err).font(.caption).foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await vm.refreshAccount() }
                }
            } else {
                LabeledContent("Signed in as", value: "—")
            }
            LabeledContent("Bearer token", value: "Stored securely")
        }
    }

    private var diagnosticsSection: some View {
        // Footer Diagnostics row — primary entry is now the
        // Connectivity section at the top of Settings, but the footer
        // entry stays for muscle-memory continuity.
        Section("Connection") {
            NavigationLink {
                DiagnosticsSheet()
                    .environment(coordinator)
            } label: {
                Label("Diagnostics", systemImage: "wrench.and.screwdriver")
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
            LabeledContent("Build", value: BuildConfig.appVersion)
        }
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
