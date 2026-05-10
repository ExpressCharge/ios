//
//  SettingsView.swift
//  ExpresScan
//
//  Settings page redesign per task #6 / UX brief. Card-based layout
//  matching the rest of the app (ReadyView, ChargerDetailView): no
//  system `Form`, every section a tinted-glass `cardSurface` card with
//  a `SectionHeader`. Customer-vs-admin gating is driven by the
//  `@Environment(\.isCustomerAccount)` flag plumbed through
//  `RootCoordinator` from `state.ownerUser.role`.
//
//  Customer mode hides: device ID, server URL, APNs environment, the
//  raw build counter, the reconnect count, raw last-sync timestamps,
//  the "Run test sync" button, and the Diagnostics navigation link.
//  In its place customers see a self-help `ConnectivityCheckCard`.
//
//  Admin mode preserves every existing capability behind the
//  `DiagnosticsLinkCard` → redesigned `DiagnosticsSheet`.
//

import AuthCore
import DeviceSync
import Networking
import SwiftUI
import UIKit
import UserNotifications

public struct SettingsView: View {

    @Environment(\.app) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isCustomerAccount) private var isCustomerAccount
    @Environment(RootCoordinator.self) private var coordinator

    @State private var viewModel: SettingsViewModel?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isShowingSignOutConfirm: Bool = false
    @State private var copyToast: String?
    @State private var connectivityCheck = ConnectivityCheckViewModel()

    public init() {}

    public var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .expressBackground()
        .toast($copyToast)
        .task {
            if viewModel == nil {
                let vm = SettingsViewModel(
                    environment: app,
                    router: coordinator,
                    settingsReader: coordinator.settingsReader
                )
                self.viewModel = vm
                await vm.refreshAccount()
            }
            await refreshNotificationStatus()
        }
    }

    @ViewBuilder
    private func content(_ vm: SettingsViewModel) -> some View {
        @Bindable var vm = vm
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                AccountIdentityCard(
                    vm: vm,
                    isCustomerAccount: isCustomerAccount,
                    onCopy: showToast
                )

                ConnectivityCard(
                    coordinator: coordinator,
                    isCustomerAccount: isCustomerAccount
                )

                ConnectivityCheckCard(viewModel: connectivityCheck)

                PermissionsCard(
                    notificationStatus: notificationStatus,
                    onOpenSystemSettings: openSystemSettings
                )

                DeviceInfoCard(
                    vm: vm,
                    isCustomerAccount: isCustomerAccount,
                    onCopy: showToast
                )

                AboutCard(isCustomerAccount: isCustomerAccount)

                if !isCustomerAccount {
                    DiagnosticsLinkCard()
                }

                SignOutCard(vm: vm, confirm: $isShowingSignOutConfirm)
            }
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.lg)
        }
        .confirmationDialog(
            "Sign out and deregister this device?",
            isPresented: $isShowingSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                Task {
                    await vm.signOut()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "You'll need to sign in again to use ExpressCharge on this iPhone."
            )
        }
    }

    // MARK: - Helpers

    private func showToast(_ message: String) {
        copyToast = message
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            self.notificationStatus = settings.authorizationStatus
        }
    }
}

// MARK: - Cards

private struct AccountIdentityCard: View {
    let vm: SettingsViewModel
    let isCustomerAccount: Bool
    let onCopy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("Account")

            HStack(spacing: Spacing.md) {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .foregroundStyle(ColorPalette.primaryCyan)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.headline)
                    if let secondary {
                        Text(secondary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if !isCustomerAccount, let registered = vm.me?.registeredAtIso {
                Divider()
                LabeledContent("Registered", value: Self.formattedRegistered(registered))
            }
        }
        .padding(Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var displayName: String {
        vm.me?.ownerDisplayName
            ?? vm.me?.ownerName
            ?? vm.me?.ownerEmail
            ?? "Signed in"
    }

    private var secondary: String? {
        guard let email = vm.me?.ownerEmail, email != displayName else { return nil }
        return email
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

private struct ConnectivityCard: View {
    let coordinator: RootCoordinator
    let isCustomerAccount: Bool

    private var status: ConnectionStatus {
        coordinator.deviceState?.connectionStatus
            ?? coordinator.scan?.connectionStatus
            ?? .offline
    }

    private var lastSync: Date? {
        coordinator.deviceState?.lastHeartbeatAt
            ?? coordinator.scan?.lastHeartbeatAt
    }

    private var reconnects: Int {
        coordinator.deviceState?.reconnectCount
            ?? coordinator.scan?.reconnectCount
            ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("Connectivity") {
                StatusPill(
                    label: status.settingsLabel,
                    systemImage: status.settingsIcon,
                    tone: status.settingsTone
                )
            }

            if isCustomerAccount {
                LabeledContent("Last update") {
                    Text(lastSync.map(Self.relative) ?? "Just connected")
                        .foregroundStyle(.secondary)
                }
            } else {
                LabeledContent("Last sync") {
                    Text(lastSync.map(Self.relative) ?? "—")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Reconnects") {
                    Text("\(reconnects)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(.tinted(status.settingsTone))
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct PermissionsCard: View {
    let notificationStatus: UNAuthorizationStatus
    let onOpenSystemSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("Permissions")
            HStack {
                Label("Notifications", systemImage: "bell.fill")
                    .labelStyle(.titleAndIcon)
                Spacer()
                StatusPill(
                    label: notificationStatus.label,
                    systemImage: notificationStatus.icon,
                    tone: notificationStatus.tone
                )
            }
            if notificationStatus == .denied || notificationStatus == .notDetermined {
                PrimaryButton(
                    "Open iOS Settings",
                    systemImage: "gear",
                    action: onOpenSystemSettings
                )
            }
        }
        .padding(Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

private struct DeviceInfoCard: View {
    let vm: SettingsViewModel
    let isCustomerAccount: Bool
    let onCopy: (String) -> Void

    var body: some View {
        @Bindable var vm = vm
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("Device")

            LabeledContent("Name") {
                TextField(
                    UIDevice.current.name,
                    text: $vm.label
                )
                .multilineTextAlignment(.trailing)
                .submitLabel(.done)
                .onSubmit { vm.commitLocalRename() }
            }

            LabeledContent("Model") {
                Text(UIDevice.current.model)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("iOS") {
                Text(UIDevice.current.systemVersion)
                    .foregroundStyle(.secondary)
            }

            if isCustomerAccount {
                LabeledContent("App") {
                    Text(BuildConfig.shortVersion)
                        .foregroundStyle(.secondary)
                }
            } else {
                LabeledContent("App") {
                    Text(BuildConfig.appVersion)
                        .foregroundStyle(.secondary)
                }
                CopyableValueRow(
                    "Device ID",
                    value: vm.me?.deviceId,
                    onCopy: { _ in onCopy("Device ID copied") }
                )
            }
        }
        .padding(Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

private struct AboutCard: View {
    let isCustomerAccount: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("About")
            Link(
                destination: URL(string: "https://manage.example.com/privacy")!
            ) {
                HStack {
                    Label("Privacy policy", systemImage: "hand.raised")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.tertiary)
                }
            }
            Link(
                destination: URL(string: "https://manage.example.com/terms")!
            ) {
                HStack {
                    Label("Terms of service", systemImage: "doc.text")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

private struct DiagnosticsLinkCard: View {
    @Environment(RootCoordinator.self) private var coordinator

    var body: some View {
        NavigationLink {
            DiagnosticsSheet().environment(coordinator)
        } label: {
            HStack {
                Label("Diagnostics", systemImage: "wrench.and.screwdriver")
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(Spacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .cardSurface()
    }
}

private struct SignOutCard: View {
    let vm: SettingsViewModel
    @Binding var confirm: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            PrimaryButton(
                vm.isSigningOut ? "Signing out…" : "Sign out",
                systemImage: "rectangle.portrait.and.arrow.right",
                variant: .destructive,
                state: vm.isSigningOut ? .loading : .default,
                action: { confirm = true }
            )
            if let err = vm.signOutError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - ConnectionStatus pill mapping (Settings)

extension ConnectionStatus {
    fileprivate var settingsLabel: String {
        switch self {
        case .offline: return "Offline"
        case .connecting: return "Connecting"
        case .online: return "Online"
        case .reconnecting: return "Reconnecting"
        }
    }
    fileprivate var settingsIcon: String {
        switch self {
        case .offline: return "wifi.slash"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .online: return "checkmark.circle.fill"
        case .reconnecting: return "arrow.triangle.2.circlepath.circle"
        }
    }
    fileprivate var settingsTone: StatusPill.Tone {
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
    fileprivate var label: String {
        switch self {
        case .notDetermined: return "Ask"
        case .denied: return "Denied"
        case .authorized: return "Allowed"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }
    fileprivate var icon: String {
        switch self {
        case .authorized, .provisional: return "checkmark.circle.fill"
        case .denied: return "xmark.octagon.fill"
        case .notDetermined: return "questionmark.circle"
        case .ephemeral: return "hourglass"
        @unknown default: return "questionmark.circle"
        }
    }
    fileprivate var tone: StatusPill.Tone {
        switch self {
        case .authorized, .provisional: return .positive
        case .denied: return .negative
        case .notDetermined, .ephemeral: return .warning
        @unknown default: return .neutral
        }
    }
}
