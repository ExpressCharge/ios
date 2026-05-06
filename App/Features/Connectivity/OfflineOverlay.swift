//
//  OfflineOverlay.swift
//  ExpresScan
//
//  Full-screen, dismiss-blocking cover shown whenever the
//  `ReachabilityMonitor` is not `.online`. Two flavours of copy
//  distinguish "your phone is offline" from "the server is down".
//
//  Auto-retry is driven by `ReachabilityMonitor`'s exponential
//  backoff loop — there's no manual "Try again" affordance. A
//  compact countdown ring in the top-right corner mirrors the
//  scan / scan-result screens' toolbar countdown so the user can
//  see progress without acting.
//

import SwiftUI

struct OfflineOverlay: View {

    let state: ReachabilityMonitor.State
    let nextProbeAt: Date?
    let currentBackoffSeconds: Int?

    var body: some View {
        ZStack(alignment: .topTrailing) {
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
                    Text(bodyText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if state == .deviceOffline {
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
                }
            }
            .padding(.horizontal, Spacing.xl)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            countdown
                .padding(.top, Spacing.base)
                .padding(.trailing, Spacing.base)
        }
        .accessibilityElement(children: .combine)
    }

    /// Top-right countdown — a `CompactCountdown` ring driven by
    /// `nextProbeAt - now`. Hidden when no probe is scheduled
    /// (`state == .online`, transient race conditions).
    @ViewBuilder
    private var countdown: some View {
        if let nextProbeAt, let total = currentBackoffSeconds, total > 0 {
            TimelineView(.animation(minimumInterval: 1.0)) { context in
                let remaining = max(
                    0, Int(nextProbeAt.timeIntervalSince(context.date).rounded(.up)))
                let progress = Double(remaining) / Double(max(total, 1))
                CompactCountdown(
                    progress: progress,
                    seconds: remaining,
                    tone: .resultDismiss
                )
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(.thinMaterial, in: Capsule())
            }
        }
    }

    private var systemImage: String {
        switch state {
        case .deviceOffline: return "wifi.exclamationmark"
        case .serverUnreachable: return "bolt.horizontal.icloud"
        case .online: return "checkmark.circle"
        }
    }

    private var title: String {
        switch state {
        case .deviceOffline: return "You're offline"
        case .serverUnreachable: return "Can't reach ExpressCharge"
        case .online: return ""
        }
    }

    private var toneColor: Color {
        switch state {
        case .deviceOffline: return ColorPalette.warningAmber
        case .serverUnreachable: return ColorPalette.destructiveRose
        case .online: return ColorPalette.success
        }
    }

    private var bodyText: String {
        switch state {
        case .deviceOffline:
            return "Reconnect to Wi-Fi or cellular to continue using ExpressCharge."
        case .serverUnreachable:
            return "Our servers aren't responding right now. We'll keep trying automatically."
        case .online:
            return ""
        }
    }
}
