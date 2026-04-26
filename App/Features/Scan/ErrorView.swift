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
    public let onRetry: () -> Void
    public let onBack: () -> Void

    public init(
        error: ScanError,
        onRetry: @escaping () -> Void = {},
        onBack: @escaping () -> Void = {}
    ) {
        self.error = error
        self.onRetry = onRetry
        self.onBack = onBack
    }

    public var body: some View {
        let info = display(for: error)

        ZStack {
            ColorPalette.background.ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                Spacer()

                Image(systemName: info.icon)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(info.tint)
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)

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
                        Button(action: onRetry) {
                            Text(info.retryLabel)
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.md)
                                .foregroundStyle(.white)
                                .background(
                                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                        .fill(ColorPalette.primaryCyan)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Back", action: onBack)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xl)
            }
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
                body: "MIFARE Classic and similar legacy cards can't be read by iPhone. Use an EV-compatible card.",
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
                body: "The scan request expired before the card was read. Ask the admin to start a new scan.",
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
                body: "The server reported an error. Please try again in a moment.",
                retryLabel: "Retry",
                showsRetry: true
            )
        }
    }
}
