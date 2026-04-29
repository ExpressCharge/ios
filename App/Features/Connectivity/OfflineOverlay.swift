//
//  OfflineOverlay.swift
//  ExpresScan
//
//  Full-screen, dismiss-blocking cover shown whenever the
//  `ReachabilityMonitor` is not `.online`. Two distinct flavors of
//  copy distinguish "your phone is offline" from "the server is
//  down" so the user knows whether to fix their network or wait.
//

import SwiftUI

struct OfflineOverlay: View {

    let state: ReachabilityMonitor.State
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            ColorPalette.background
                .ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                Image(systemName: systemImage)
                    .font(.system(size: 84, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(toneColor)

                VStack(spacing: Spacing.sm) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(body(for: state))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                actions
            }
            .padding(.horizontal, Spacing.xl)
            .frame(maxWidth: 420)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var actions: some View {
        switch state {
        case .deviceOffline:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .serverUnreachable:
            Button {
                onRetry()
            } label: {
                Label("Try again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .online:
            EmptyView()
        }
    }

    private var systemImage: String {
        switch state {
        case .deviceOffline:     return "wifi.exclamationmark"
        case .serverUnreachable: return "bolt.horizontal.icloud"
        case .online:            return "checkmark.circle"
        }
    }

    private var title: String {
        switch state {
        case .deviceOffline:     return "You're offline"
        case .serverUnreachable: return "Can't reach ExpresScan"
        case .online:            return ""
        }
    }

    private var toneColor: Color {
        switch state {
        case .deviceOffline:     return ColorPalette.warningAmber
        case .serverUnreachable: return ColorPalette.destructiveRose
        case .online:            return ColorPalette.success
        }
    }

    private func body(for state: ReachabilityMonitor.State) -> String {
        switch state {
        case .deviceOffline:
            return "Reconnect to Wi-Fi or cellular to continue using ExpresScan."
        case .serverUnreachable:
            return "Our servers aren't responding right now. We'll reconnect automatically as soon as they're back."
        case .online:
            return ""
        }
    }
}
