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

    @State private var deviceLabel: String = UIDevice.current.name
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isShowingSignOutConfirm: Bool = false
    @State private var isSigningOut: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                deviceSection
                notificationsSection
                accountSection
                aboutSection

                Section {
                    Button(role: .destructive) {
                        isShowingSignOutConfirm = true
                    } label: {
                        if isSigningOut {
                            HStack {
                                ProgressView()
                                Text("Signing out…")
                            }
                        } else {
                            Text("Sign out")
                        }
                    }
                    .disabled(isSigningOut)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await refreshNotificationStatus() }
            .confirmationDialog(
                "Sign out and deregister this device?",
                isPresented: $isShowingSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive, action: handleSignOut)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This iPhone will stop receiving scan requests. You'll need to sign in again to use ExpresScan.")
            }
        }
    }

    // MARK: - Sections

    private var deviceSection: some View {
        Section("Device") {
            // The label edit lands in E-app-wire — we PUT against the
            // admin-rename endpoint via owner-cookie or an
            // owner-rename endpoint. Skeleton: read-only.
            LabeledContent("Name", value: deviceLabel)
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

    private var accountSection: some View {
        Section("Account") {
            // E-app-wire fills these from `GET /api/devices/me`.
            LabeledContent("Signed in as", value: "—")
            LabeledContent("Bearer token", value: "Stored securely")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Link(destination: URL(string: "https://manage.example.com/privacy")!) {
                Label("Privacy policy", systemImage: "hand.raised")
            }
            Link(destination: URL(string: "https://manage.example.com/terms")!) {
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

    private func handleSignOut() {
        guard !isSigningOut else { return }
        isSigningOut = true
        Task {
            // E-app-wire: also POST DELETE /api/devices/{deviceId}
            // BEFORE clearing Keychain so the server-side device row
            // is removed. If the network call fails (offline), we
            // still clear local state.
            try? await app.authStore.deleteAll()
            await MainActor.run {
                self.isSigningOut = false
                coordinator.didSignOut()
                dismiss()
            }
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
