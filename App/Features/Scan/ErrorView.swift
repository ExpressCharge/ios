//
//  ErrorView.swift
//  ExpresScan
//
//  Generic error surface — one screen with five branded variants
//  selected by the `ScanError` case. Each variant carries a distinct
//  recovery copy. The leading icon is the shared red `xmark` from
//  `ScanIconView` so the matched-geometry morph from the scan-active
//  center is continuous.
//
//  Slice N (a640f12) added the matched-geometry icon + the 10s
//  auto-dismiss back to ready.
//
//  Slice N+1 adds the chrome:
//    - top-left: native iOS back button (early-dismiss path);
//    - top-right: a small `CompactCountdown` ring, white-tinted, that
//      depletes with the auto-dismiss.
//
//  Spec: `50-ios.md` § "UX details" → "Error states".
//

import SwiftUI

public struct ErrorView: View {

    public let error: ScanError
    public let iconNamespace: Namespace.ID?
    public let onRetry: () -> Void
    public let onBack: () -> Void

    /// Seconds before auto-return to ready.
    private static let autoDismissSeconds: TimeInterval = 10

    @State private var deadline: Date?
    @State private var didDismiss: Bool = false

    public init(
        error: ScanError,
        iconNamespace: Namespace.ID? = nil,
        onRetry: @escaping () -> Void = {},
        onBack: @escaping () -> Void = {}
    ) {
        self.error = error
        self.iconNamespace = iconNamespace
        self.onRetry = onRetry
        self.onBack = onBack
    }

    public var body: some View {
        let info = display(for: error)

        ZStack {
            ColorPalette.background.ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                Spacer()

                // Uses the shared matched-geometry icon (red x) so the
                // morph from the scan-active center is continuous.
                ScanIconView(
                    mode: .result(.failure),
                    size: 96,
                    namespace: iconNamespace
                )

                VStack(spacing: Spacing.sm) {
                    Text(info.title)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(info.body)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                }

                Spacer()

                if info.showsRetry {
                    PrimaryButton(info.retryLabel, action: onRetry)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.bottom, Spacing.xl)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismissNow()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
            }
            if let deadline {
                ToolbarItem(placement: .topBarTrailing) {
                    TimelineView(.animation(minimumInterval: 1.0)) { context in
                        let remaining = max(0, deadline.timeIntervalSince(context.date))
                        CompactCountdown(
                            progress: remaining / Self.autoDismissSeconds,
                            seconds: Int(remaining.rounded(.up)),
                            tone: .resultDismiss
                        )
                        .onChange(of: remaining <= 0) { _, expired in
                            if expired { dismissNow() }
                        }
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if deadline == nil {
                deadline = Date().addingTimeInterval(Self.autoDismissSeconds)
            }
        }
    }

    private func dismissNow() {
        guard !didDismiss else { return }
        didDismiss = true
        onBack()
    }

    private struct Display {
        let icon: String
        let tint: Color
        let title: String
        let body: String
        let retryLabel: String
        let showsRetry: Bool
    }

    private func display(for error: ScanError) -> Display {
        switch error {
        case .timeout:
            return Display(
                icon: "clock.badge.exclamationmark",
                tint: ColorPalette.warningAmber,
                title: "Scan timed out",
                body: "We didn't see a card. Hold the card to the top of your iPhone and try again.",
                retryLabel: "Try again",
                showsRetry: true
            )
        case .unsupportedCard:
            return Display(
                icon: "shield.lefthalf.filled.slash",
                tint: ColorPalette.destructiveRose,
                title: "Card not supported",
                body: "This card isn't supported. Try a different NFC card.",
                retryLabel: "Try a different card",
                showsRetry: true
            )
        case .network:
            return Display(
                icon: "icloud.slash.fill",
                tint: ColorPalette.destructiveRose,
                title: "Couldn't reach ExpressCharge",
                body: "Check your network connection. We'll retry as soon as you're back online.",
                retryLabel: "Retry",
                showsRetry: true
            )
        case .pairingExpired:
            return Display(
                icon: "timer.circle.fill",
                tint: ColorPalette.warningAmber,
                title: "Scan expired",
                body: "The scan request expired. Ask the admin to start a new scan.",
                retryLabel: "Back to ready",
                showsRetry: false
            )
        case .tokenRevoked:
            return Display(
                icon: "person.crop.circle.badge.xmark",
                tint: ColorPalette.destructiveRose,
                title: "Signed out",
                body: "An admin signed this device out. Sign in again to continue.",
                retryLabel: "Sign in",
                showsRetry: true
            )
        case .server:
            return Display(
                icon: "exclamationmark.octagon.fill",
                tint: ColorPalette.destructiveRose,
                title: "Something went wrong",
                body: "Something went wrong. Please try again.",
                retryLabel: "Retry",
                showsRetry: true
            )
        }
    }
}
