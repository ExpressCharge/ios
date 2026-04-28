//
//  ErrorView.swift
//  ExpresScan
//
//  Generic error surface — one screen with five branded variants
//  selected by the `ScanError` case. Each variant carries a distinct
//  icon (NOT just colour) and a unique recovery copy.
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
    private static let autoDismissSeconds: UInt64 = 10

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

                VStack(spacing: Spacing.sm) {
                    if info.showsRetry {
                        PrimaryButton(info.retryLabel, action: onRetry)
                    }

                    Button("Back", action: onBack)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xl)
            }
        }
        .task {
            // Auto-dismiss back to ready after 10s. Mirrors the
            // SuccessView behaviour. The user can still tap the Back
            // button to dismiss earlier; the manual Retry button (when
            // shown) re-arms a scan via the coordinator.
            try? await Task.sleep(
                nanoseconds: Self.autoDismissSeconds * 1_000_000_000
            )
            guard !Task.isCancelled else { return }
            onBack()
        }
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
                title: "Couldn't reach ExpresSync",
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
