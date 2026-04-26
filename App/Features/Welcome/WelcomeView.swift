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

import SwiftUI

import AuthCore

public struct WelcomeView: View {

    /// When `true`, the LoginViewModel is presenting an
    /// ASWebAuthenticationSession on top of this view. Used so we can
    /// re-render the CTA in a "Signing in…" state without changing the
    /// underlying screen.
    public let showingLoginActivity: Bool

    @Environment(\.app) private var app
    @Environment(RootCoordinator.self) private var coordinator

    @State private var loginViewModel = LoginViewModel()

    public init(showingLoginActivity: Bool = false) {
        self.showingLoginActivity = showingLoginActivity
    }

    public var body: some View {
        ZStack {
            ColorPalette.background
                .ignoresSafeArea()

            VStack(spacing: Spacing.xl) {
                Spacer()

                // Logo + NFC glyph.
                VStack(spacing: Spacing.lg) {
                    Image(systemName: "bolt.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(ColorPalette.primaryCyan)
                        .frame(height: 56)
                        .accessibilityLabel("ExpresScan")

                    Image(systemName: "wave.3.right.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(ColorPalette.primaryCyan)
                        .frame(width: 96, height: 96)
                        .accessibilityHidden(true)
                }

                // Heading + body.
                VStack(spacing: Spacing.md) {
                    Text("ExpresScan")
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text("Turn your iPhone into an NFC card reader for ExpresSync. Sign in with your admin or customer account to register this device.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                }

                Spacer()

                // CTA.
                Button(action: handleSignInTapped) {
                    HStack(spacing: Spacing.sm) {
                        if showingLoginActivity || loginViewModel.isPresenting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        }
                        Text("Sign in to ExpresSync")
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
                .disabled(showingLoginActivity || loginViewModel.isPresenting)
                .accessibilityHint("Opens Safari to sign in to your ExpresSync account.")
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xl)
            }
        }
        .onChange(of: loginViewModel.deliveredCode) { _, newCode in
            // The login VM hands a one-time code back via this property.
            // The Universal Link callback (SceneDelegate) is the actual
            // delivery channel; the LoginViewModel observes it.
            if let code = newCode, !code.isEmpty {
                coordinator.didReceiveOneTimeCode(code)
            }
        }
        .onChange(of: loginViewModel.isPresenting) { _, presenting in
            if presenting {
                coordinator.startLogin()
            } else if !presenting && coordinator.route == .loggingIn && loginViewModel.deliveredCode == nil {
                // User cancelled the web sheet.
                coordinator.cancelLogin()
            }
        }
    }

    private func handleSignInTapped() {
        loginViewModel.start()
    }
}
