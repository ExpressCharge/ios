//
//  WelcomeView.swift
//  ExpresScan
//
//  First-run welcome screen. Shows the brand logo + a 96 pt static NFC
//  glyph, headline, body copy, and a single CTA — "Sign in to
//  ExpresSync." Tap presents the `ASWebAuthenticationSession` with PKCE
//  via `LoginViewModel`.
//
//  Spec: `50-ios.md` § "UX details" → "Welcome".
//

import AuthCore
import SwiftUI

public struct WelcomeView: View {

    /// When `true`, the LoginViewModel is presenting an
    /// ASWebAuthenticationSession on top of this view. Used so we can
    /// re-render the CTA in a "Signing in…" state without changing the
    /// underlying screen.
    public let showingLoginActivity: Bool

    @Environment(\.app) private var app
    @Environment(RootCoordinator.self) private var coordinator

    @State private var loginViewModel = LoginViewModel()

    /// Surfaced from `RootView.runQrSignIn` via the
    /// `qrSignInError` notification when an iOS-only QR sign-in
    /// attempt fails. Displayed as a top banner; auto-dismisses
    /// after ~5 s.
    @State private var qrSignInError: String?
    @State private var qrSignInAutoHide: Task<Void, Never>?

    public init(showingLoginActivity: Bool = false) {
        self.showingLoginActivity = showingLoginActivity
    }

    public var body: some View {
        ZStack {
            ColorPalette.background
                .ignoresSafeArea()

            VStack(spacing: Spacing.xl) {
                Spacer()

                // Brand lockup (squircle logo + animated wordmark).
                BrandLockup(.login)

                // Subhead body copy.
                Text(
                    "Welcome to ExpressCharge. Sign in to control your chargers and use this iPhone as an NFC tap reader."
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)

                Spacer()

                // CTA.
                PrimaryButton(
                    "Sign in",
                    state: (showingLoginActivity || loginViewModel.isPresenting)
                        ? .loading : .default,
                    action: handleSignInTapped
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xl)
                .accessibilityHint("Opens Safari to sign in to your ExpressCharge account.")
            }

            // QR sign-in error banner. Renders only when set; the
            // notification observer below sets it from
            // `AppNotifications.qrSignInError`.
            if let message = qrSignInError {
                VStack {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.white)
                        Text(message)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            dismissQrSignInError()
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .accessibilityLabel("Dismiss error")
                    }
                    .padding(Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(ColorPalette.destructiveRose)
                    )
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.md)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: qrSignInError)
        .onReceive(
            NotificationCenter.default.publisher(
                for: AppNotifications.qrSignInError)
        ) { note in
            let message =
                (note.userInfo?["message"] as? String)
                ?? "Couldn't sign in. Try scanning again."
            qrSignInError = message
            qrSignInAutoHide?.cancel()
            qrSignInAutoHide = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if !Task.isCancelled { qrSignInError = nil }
            }
        }
        .onChange(of: loginViewModel.deliveredCode) { _, newCode in
            // The login VM hands a one-time code back via this property.
            // The Universal Link callback (SceneDelegate) is the actual
            // delivery channel; the LoginViewModel observes it.
            if let code = newCode, !code.isEmpty {
                let verifier = loginViewModel.lastVerifier ?? ""
                coordinator.didReceiveOneTimeCode(code, codeVerifier: verifier)
                loginViewModel.acknowledgeCode()
            }
        }
        .onChange(of: loginViewModel.isPresenting) { _, presenting in
            if presenting {
                coordinator.startLogin()
            } else if !presenting && coordinator.route == .loggingIn
                && loginViewModel.deliveredCode == nil
            {
                // User cancelled the web sheet.
                coordinator.cancelLogin()
            }
        }
    }

    private func handleSignInTapped() {
        loginViewModel.start()
    }

    private func dismissQrSignInError() {
        qrSignInAutoHide?.cancel()
        qrSignInError = nil
    }
}
