//
//  NotificationPrimingView.swift
//  ExpresScan
//
//  Pre-permission priming screen — explains WHY we want notifications
//  before showing the system prompt. Per Apple HIG, this lifts opt-in
//  rates significantly and avoids a dead-end "Ask Next Launch" path.
//
//  Spec: `50-ios.md` § "UX details" → "Notification priming".
//

import SwiftUI
import UIKit
import UserNotifications

public struct NotificationPrimingView: View {

    @Environment(RootCoordinator.self) private var coordinator
    @State private var isRequesting: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            // Brand glyph.
            Image(systemName: "bell.badge.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(ColorPalette.primaryCyan)
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.md) {
                Text("Allow notifications")
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)

                Text("ExpresScan uses notifications to wake your iPhone the moment a charging station or admin needs to scan a card. Without notifications, scans may be missed when the app is closed.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }

            Spacer()

            VStack(spacing: Spacing.md) {
                Button(action: handleAllowTapped) {
                    HStack(spacing: Spacing.sm) {
                        if isRequesting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        }
                        Text("Allow Notifications")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(ColorPalette.primaryCyan)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRequesting)

                Button("Not now") {
                    coordinator.didFinishPriming()
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .disabled(isRequesting)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
        .background(ColorPalette.background.ignoresSafeArea())
    }

    private func handleAllowTapped() {
        isRequesting = true
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                self.isRequesting = false
                self.coordinator.didFinishPriming()
            }
        }
    }
}
