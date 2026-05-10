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
    @State private var apnsStatus: ApnsRegistrationStatus = .pending
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
            LazyVStack(alignment: .leading, spacing: Spacing.md) {
                AccountIdentityCard(
                    vm: vm,
                    isCustomerAccount: isCustomerAccount,
                    onCopy: showToast
                )

                ConnectivityCard(
                    coordinator: coordinator,
                    isCustomerAccount: isCustomerAccount,
                    connectivityCheck: connectivityCheck
                )

                PermissionsCard(
                    notificationStatus: notificationStatus,
                    apnsStatus: apnsStatus,
                    onOpenSystemSettings: openSystemSettings,
                    onRetryRegister: retryApnsRegistration
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
            "Sign Out of ExpressCharge?",
            isPresented: $isShowingSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
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

    /// Re-arm the APNs registration handshake. Asks UIApplication to
    /// re-register; the AppDelegate's
    /// `didRegisterForRemoteNotificationsWithDeviceToken` /
    /// `didFailToRegister...` callbacks then notify back.
    private func retryApnsRegistration() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            self.notificationStatus = settings.authorizationStatus
            self.apnsStatus = Self.deriveApnsStatus(
                notificationAuth: settings.authorizationStatus,
                push: app.pushService
            )
        }
    }

    /// Coarse-grained APNs registration state for the Settings UI.
    /// Sourced from a few synchronous reads on `PushService`; surfaces
    /// the most actionable state to the user without exposing the
    /// underlying token.
    fileprivate enum ApnsRegistrationStatus: Equatable {
        case pending          // Notifications authorised, waiting for APNs
        case registered       // Token uploaded to server
        case unauthorized     // Notifications denied/notDetermined
        case failed           // APNs returned an error
    }

    fileprivate static func deriveApnsStatus(
        notificationAuth: UNAuthorizationStatus,
        push: PushService?
    ) -> ApnsRegistrationStatus {
        switch notificationAuth {
        case .denied, .notDetermined:
            return .unauthorized
        default:
            break
        }
        guard let push else { return .pending }
        if push.lastApnsRegistrationFailed { return .failed }
        if push.lastUploadedTokenSnapshot != nil { return .registered }
        return .pending
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.headline)
                    if let secondary {
                        Text(secondary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    PlanBadge(
                        ownerRole: vm.me?.ownerRole,
                        planCode: vm.me?.planCode,
                        planName: vm.me?.planName
                    )
                }
                Spacer(minLength: 0)
            }
        }
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
}

private struct ConnectivityCard: View {
    let coordinator: RootCoordinator
    let isCustomerAccount: Bool
    /// Embedded self-test (formerly the standalone
    /// `ConnectivityCheckCard`). Per 2026-05 UX feedback the two
    /// surfaces are merged so the user sees status + active check
    /// in one card.
    let connectivityCheck: ConnectivityCheckViewModel

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

            // Inline self-test rows. The user can run a fresh check
            // without leaving the Settings card; results land
            // in-place under the status block above.
            Divider()
                .padding(.vertical, Spacing.xs)
            ConnectivityCheckCard(viewModel: connectivityCheck, inline: true)
        }
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
    let apnsStatus: SettingsView.ApnsRegistrationStatus
    let onOpenSystemSettings: () -> Void
    let onRetryRegister: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("Permissions")
            HStack {
                Label("Notifications", systemImage: "bell")
                    .labelStyle(.titleAndIcon)
                Spacer()
                StatusPill(
                    label: notificationStatus.label,
                    systemImage: notificationStatus.icon,
                    tone: notificationStatus.tone
                )
            }
            // Phase 2 polish — APNs registration row. Notifications
            // permission is necessary but not sufficient: iOS needs to
            // hand back a push token AND we need to PUT it to the
            // server. Surface that distinction so the user can see
            // when registration is the actual blocker.
            HStack {
                Label("Push token", systemImage: "antenna.radiowaves.left.and.right")
                    .labelStyle(.titleAndIcon)
                Spacer()
                StatusPill(
                    label: apnsStatus.label,
                    systemImage: apnsStatus.icon,
                    tone: apnsStatus.tone
                )
            }
            if notificationStatus == .denied || notificationStatus == .notDetermined {
                PrimaryButton(
                    "Open iOS Settings",
                    systemImage: "gear",
                    action: onOpenSystemSettings
                )
                .padding(.top, Spacing.sm)
            } else if apnsStatus == .failed {
                PrimaryButton(
                    "Retry Registration",
                    systemImage: "arrow.clockwise",
                    action: onRetryRegister
                )
                .padding(.top, Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

extension SettingsView.ApnsRegistrationStatus {
    fileprivate var label: String {
        switch self {
        case .registered: return "Registered"
        case .pending: return "Waiting"
        case .unauthorized: return "Not authorised"
        case .failed: return "Failed"
        }
    }
    fileprivate var icon: String {
        switch self {
        case .registered: return "checkmark.circle.fill"
        case .pending: return "ellipsis.circle"
        case .unauthorized: return "lock.slash"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
    fileprivate var tone: StatusPill.Tone {
        switch self {
        case .registered: return .positive
        case .pending: return .info
        case .unauthorized: return .neutral
        case .failed: return .negative
        }
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
                    Label("Privacy Policy", systemImage: "hand.raised")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.tertiary)
                }
            }
            Link(
                destination: URL(string: "https://manage.example.com/terms")!
            ) {
                HStack {
                    Label("Terms of Service", systemImage: "doc.text")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.tertiary)
                }
            }
        }
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
                Image(systemName: "chevron.forward")
                    .foregroundStyle(.secondary)
            }
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
                vm.isSigningOut ? "Signing Out…" : "Sign Out",
                systemImage: "rectangle.portrait.and.arrow.right",
                variant: .destructive,
                state: vm.isSigningOut ? .loading : .default,
                action: { confirm = true }
            )
            if let err = vm.signOutError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, Spacing.base)
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
