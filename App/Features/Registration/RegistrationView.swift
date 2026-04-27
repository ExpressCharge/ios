//
//  RegistrationView.swift
//  ExpresScan
//
//  Pre-fills the device label from `UIDevice.current.name`, lets the
//  user rename it, and submits via `RegistrationViewModel`.
//
//  Spec: `50-ios.md` § "UX details" → "Register".
//

import SwiftUI
import UIKit

public struct RegistrationView: View {

    @Environment(\.app) private var app
    @Environment(RootCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: RegistrationViewModel?

    /// One-time code delivered by the Universal Link. Required for the
    /// view to do anything useful — we never construct it without one.
    public let oneTimeCode: String

    /// PKCE verifier matching the challenge that was passed to the web
    /// flow. Carried through from `WelcomeView` via `RootCoordinator`'s
    /// `.registering(oneTimeCode:codeVerifier:)` route — explicit DI,
    /// no process singletons.
    public let codeVerifier: String

    public init(oneTimeCode: String, codeVerifier: String) {
        self.oneTimeCode = oneTimeCode
        self.codeVerifier = codeVerifier
    }

    public var body: some View {
        // SwiftUI cannot infer the view-model lifetime from a non-State
        // property, so we lazily construct on first appearance.
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .task {
            if viewModel == nil {
                self.viewModel = RegistrationViewModel(
                    environment: app,
                    oneTimeCode: oneTimeCode,
                    codeVerifier: codeVerifier
                )
                self.viewModel?.startObservingApnsToken()
                // Best-effort: wait briefly for an APNs token before
                // submitting. RegistrationViewModel.submit() reads the
                // last token observed at call-time.
                self.viewModel?.startWaitingForApnsToken()
            }
        }
        .onDisappear {
            viewModel?.stopObservingApnsToken()
        }
        .background(ColorPalette.background.ignoresSafeArea())
    }

    @ViewBuilder
    private func content(_ vm: RegistrationViewModel) -> some View {
        @Bindable var vm = vm

        VStack(spacing: Spacing.lg) {
            Spacer()

            VStack(spacing: Spacing.md) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(ColorPalette.primaryCyan)
                    .frame(height: 64)
                    .accessibilityHidden(true)

                Text("Register this iPhone")
                    .font(.title.weight(.bold))

                Text("Give your iPhone a name so admins can identify it. You can change it later in Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }

            // Label field.
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Device name")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("My iPhone", text: $vm.label)
                    .textFieldStyle(.plain)
                    .padding(Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(ColorPalette.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(ColorPalette.borderSubtle, lineWidth: 1)
                    )
                    .submitLabel(.done)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.words)
            }
            .padding(.horizontal, Spacing.lg)

            // Error.
            if let error = vm.error {
                ErrorBanner(message: copy(for: error))
                    .padding(.horizontal, Spacing.lg)
            }

            Spacer()

            // CTA.
            PrimaryButton(
                "Register",
                state: state(for: vm),
                action: { Task { await vm.submit() } }
            )
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
        .onChange(of: vm.didSucceed) { _, success in
            if success {
                coordinator.didCompleteRegistration()
            }
        }
    }

    private func state(for vm: RegistrationViewModel) -> PrimaryButton.State {
        if vm.isSubmitting { return .loading }
        if vm.label.trimmingCharacters(in: .whitespaces).isEmpty { return .disabled }
        return .default
    }

    private func copy(for error: RegistrationError) -> String {
        switch error {
        case .codeExpired:
            return "Sign-in code expired. Tap Sign in to try again."
        case .unauthorized:
            return "Sign-in code was rejected. Tap Sign in to try again."
        case .rateLimited:
            return "Too many attempts. Please wait a minute and try again."
        case .network:
            return "Network problem. Check your connection and try again."
        case .keychain:
            return "Couldn't save credentials securely on this device."
        case .server:
            return "The server returned an error. Please try again."
        case .other:
            return "Something went wrong. Please try again."
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ColorPalette.destructiveRose)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(ColorPalette.destructiveRose.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(ColorPalette.destructiveRose.opacity(0.30), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

