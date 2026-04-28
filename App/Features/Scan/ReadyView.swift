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
    @State private var isShowingHow: Bool = false
    @State private var isShowingDiagnostics: Bool = false
    /// Shared namespace for the matched-geometry icon morph between the
    /// hero (Ready), the active scan center, and the result screens.
    /// Lives here because all four screens render as cases of `content`
    /// inside this view's body — they're structural siblings.
    @Namespace private var iconNamespace

    public init() {}

    public var body: some View {
        ZStack {
            ColorPalette.background.ignoresSafeArea()
            content
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
                        secondsRemaining: secondsRemaining(
                            for: request,
                            now: context.date
                        ),
                        iconNamespace: iconNamespace,
                        onCancel: { scan.cancelActiveScan() }
                    )
                }
            case .success(let result):
                SuccessView(
                    result: result,
                    iconNamespace: iconNamespace,
                    onDismiss: { scan.dismissResult() }
                )
            case .error(let error):
                ErrorView(
                    error: error,
                    iconNamespace: iconNamespace,
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
            // Brand + settings live in the navigation toolbar (see the
            // `.toolbar` block below) so they sit on the same vertical
            // band. Active scan / result screens render their own
            // toolbar (CompactCountdown only) and intentionally drop
            // the settings button.
            Spacer()

            // Hero: animated NFC glyph + label. The glyph participates
            // in a `matchedGeometryEffect` so it morphs position into
            // the ScanActive / Success / Error screens when the
            // coordinator transitions out of `.idle / .connecting /
            // .readyToScan / .offline`.
            VStack(spacing: Spacing.lg) {
                ScanIconView(
                    mode: .idle(tone: heroTone(scan: scan)),
                    size: 96,
                    namespace: iconNamespace
                )
                Text(heroTitle(scan: scan))
                    .font(.largeTitle.weight(.bold))
                if let body = heroBody(scan: scan) {
                    Text(body)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                }
                // Inline connection chip — visible only when state ≠
                // online (per UX research P1-1). Tappable to surface
                // diagnostics. Hidden when online for clean chrome.
                // Inline connection chip — sourced from
                // `DeviceStateCoordinator` (slice G) when available so
                // it reflects the consolidated sync's status, not just
                // the SSE link. Falls back to the scan coordinator's
                // surface for tests / older transitions.
                let pillStatus: ConnectionStatus = coordinator.deviceState?.connectionStatus
                    ?? scan?.connectionStatus
                    ?? .offline
                if pillStatus != .online {
                    connectionPill(status: pillStatus)
                        .onTapGesture { isShowingDiagnostics = true }
                        .accessibilityHint("Tap to open diagnostics")
                }
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
            .padding(.bottom, Spacing.lg)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BrandLockup(.compact)
            }
            SettingsToolbarMenuButton()
        }
    }

    // MARK: - Hero / pill helpers

    private func connectionPill(status: ConnectionStatus) -> some View {
        StatusPill(
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

    /// Returns the state-specific subtitle, or `nil` for the default
    /// idle/ready states where we now omit the static "wait for a
    /// scan" copy entirely. Connecting and offline keep their
    /// state-meaningful copy.
    private func heroBody(scan: ScanCoordinator?) -> String? {
        switch scan?.state {
        case .connecting?:
            return "Linking to ExpressCharge…"
        case .offline?:
            return "We'll reconnect as soon as you're back online."
        default:
            return nil
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

    /// Whole seconds left before the server-stamped expiry. Drives the
    /// `CompactCountdown` toolbar indicator (Slice N+1).
    private func secondsRemaining(
        for request: ScanRequest,
        now: Date
    ) -> Int {
        let expires = TimeInterval(request.expiresAtEpochMs) / 1000.0
        let remaining = expires - now.timeIntervalSince1970
        return max(0, Int(remaining.rounded(.up)))
    }

    private var howThisWorksContent: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Bullet(symbol: "1.circle.fill", text: "Stay signed in. The app keeps a secure, low-power link to ExpressCharge.")
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
