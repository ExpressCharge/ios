//
//  ReadyView.swift
//  ExpresScan
//
//  The "home" screen post-registration. Shows brand, status pill,
//  animated NFC glyph, "Ready to Scan" hero, "How this works"
//  disclosure, and a footer with Settings + Sign-out.
//
//  Wired to `RootCoordinator.scan` (a live `ScanCoordinator`). The
//  status pill reflects SSE / push state; the body switches between
//  the ready hero, the active scan view, success, and error variants
//  driven by `ScanCoordinator.state`.
//
//  Spec: `50-ios.md` § "UX details" → "Ready home".
//

import SwiftUI

import Models

public struct ReadyView: View {

    @Environment(\.app) private var app
    @Environment(RootCoordinator.self) private var coordinator
    @State private var isShowingSettings: Bool = false
    @State private var isShowingHow: Bool = false
    @State private var isShowingDiagnostics: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            ColorPalette.background.ignoresSafeArea()
            content
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
                .environment(coordinator)
                .presentationDetents([.medium, .large])
                .presentationBackground(.thinMaterial)
                .presentationCornerRadius(32)
        }
        .sheet(isPresented: $isShowingDiagnostics) {
            DiagnosticsSheet()
                .environment(coordinator)
                .presentationDetents([.medium, .large])
                .presentationBackground(.thinMaterial)
                .presentationCornerRadius(32)
        }
        .onAppear {
            // First-render side effects only — the coordinator's
            // own lifecycle hooks (start/stop) are fired by
            // RootCoordinator transitions.
            if let scan = coordinator.scan, case .idle = scan.state {
                scan.startConnecting()
            }
        }
    }

    // The body is a switch on the scan state — distinct screens for
    // active scan / success / error. Ready and offline share the same
    // chrome.
    @ViewBuilder
    private var content: some View {
        if let scan = coordinator.scan {
            switch scan.state {
            case .scanRequested(let request), .scanning(let request):
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    ScanActiveView(
                        request: request,
                        progress: progressNow(
                            for: request,
                            armedAt: scan.armedAt,
                            now: context.date
                        ),
                        onCancel: { scan.cancelActiveScan() }
                    )
                }
            case .success(let result):
                SuccessView(
                    result: result,
                    onScanAnother: { scan.dismissResult() },
                    onBackToReady: { scan.dismissResult() }
                )
            case .error(let error):
                ErrorView(
                    error: error,
                    onRetry: { scan.dismissResult() },
                    onBack: { scan.dismissResult() }
                )
            case .idle, .connecting, .readyToScan, .offline:
                readyChrome(scan: scan)
            }
        } else {
            readyChrome(scan: nil)
        }
    }

    private func readyChrome(scan: ScanCoordinator?) -> some View {
        VStack(spacing: Spacing.lg) {
            // Brand row (top-left lockup, top-right status pill).
            HStack {
                BrandLockup(.compact)
                Spacer()
                connectionPill(scan: scan)
                    .onTapGesture { isShowingDiagnostics = true }
                    .accessibilityHint("Tap to open diagnostics")
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)

            Spacer()

            // Hero: animated NFC glyph + label.
            VStack(spacing: Spacing.lg) {
                AnimatedNFCGlyph(size: 96, tone: heroTone(scan: scan))
                Text(heroTitle(scan: scan))
                    .font(.largeTitle.weight(.bold))
                Text(heroBody(scan: scan))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
                if let scan, scan.pendingScanResultCount > 0 {
                    StatusPill(
                        label: "\(scan.pendingScanResultCount) pending upload\(scan.pendingScanResultCount == 1 ? "" : "s")",
                        systemImage: "clock.fill",
                        tone: .warning
                    )
                }
            }

            Spacer()

            // How this works disclosure.
            DisclosureGroup(
                isExpanded: $isShowingHow,
                content: { howThisWorksContent },
                label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(ColorPalette.primaryCyan)
                        Text("How this works")
                            .font(.callout.weight(.semibold))
                    }
                }
            )
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(ColorPalette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(ColorPalette.borderSubtle, lineWidth: 1)
            )
            .padding(.horizontal, Spacing.lg)

            // Footer.
            HStack {
                Button {
                    isShowingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .font(.callout)
                }
                Spacer()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.lg)
        }
    }

    // MARK: - Hero / pill helpers

    private func connectionPill(scan: ScanCoordinator?) -> some View {
        let status = scan?.connectionStatus ?? .offline
        return StatusPill(
            label: status.label,
            systemImage: status.systemImage,
            tone: status.tone
        )
    }

    private func heroTitle(scan: ScanCoordinator?) -> String {
        switch scan?.state {
        case .connecting?: return "Connecting…"
        case .offline?:    return "Offline"
        default:           return "Ready to Scan"
        }
    }

    private func heroBody(scan: ScanCoordinator?) -> String {
        switch scan?.state {
        case .connecting?:
            return "Linking to ExpresSync…"
        case .offline?:
            return "We'll reconnect as soon as you're back online."
        default:
            return "Wait for a charging station or admin to start a scan."
        }
    }

    private func heroTone(scan: ScanCoordinator?) -> StatusPill.Tone {
        switch scan?.state {
        case .offline?:    return .neutral
        case .connecting?: return .info
        default:           return .info
        }
    }

    private func progressNow(
        for request: ScanRequest,
        armedAt: Date?,
        now: Date
    ) -> Double {
        guard let armedAt else { return 1.0 }
        let expires = TimeInterval(request.expiresAtEpochMs) / 1000.0
        let total = expires - armedAt.timeIntervalSince1970
        guard total > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(armedAt)
        return max(0, min(1, 1 - elapsed / total))
    }

    private var howThisWorksContent: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Bullet(symbol: "1.circle.fill", text: "Stay signed in. The app keeps a secure, low-power link to ExpresSync.")
            Bullet(symbol: "2.circle.fill", text: "When a charging station or admin starts a scan, your iPhone vibrates.")
            Bullet(symbol: "3.circle.fill", text: "Hold the card to the top of your iPhone. The result appears on screen.")
        }
        .padding(.top, Spacing.sm)
    }
}

private struct Bullet: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: symbol)
                .foregroundStyle(ColorPalette.primaryCyan)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - ConnectionStatus pill mapping

private extension ConnectionStatus {
    var label: String {
        switch self {
        case .offline: return "Offline"
        case .connecting: return "Connecting"
        case .online: return "Online"
        case .reconnecting: return "Reconnecting"
        }
    }

    var systemImage: String {
        switch self {
        case .offline: return "wifi.slash"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .online: return "checkmark.circle.fill"
        case .reconnecting: return "arrow.triangle.2.circlepath.circle"
        }
    }

    var tone: StatusPill.Tone {
        switch self {
        case .offline: return .negative
        case .connecting: return .info
        case .online: return .positive
        case .reconnecting: return .warning
        }
    }
}
