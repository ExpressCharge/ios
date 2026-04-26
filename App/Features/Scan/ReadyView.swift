//
//  ReadyView.swift
//  ExpresScan
//
//  The "home" screen post-registration. Shows brand, status pill,
//  animated NFC glyph, "Ready to Scan" hero, "How this works"
//  disclosure, and a footer with Settings + Sign-out.
//
//  Wave-3 (this track) ships the static layout. Wave-4 (E-app-wire)
//  drops in the live `ScanCoordinator` so the status pill and the
//  NFC-glyph animation reflect SSE / push state.
//
//  Spec: `50-ios.md` § "UX details" → "Ready home".
//

import SwiftUI

public struct ReadyView: View {

    @Environment(\.app) private var app
    @Environment(RootCoordinator.self) private var coordinator
    @State private var isShowingSettings: Bool = false
    @State private var isShowingHow: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                ColorPalette.background.ignoresSafeArea()

                VStack(spacing: Spacing.lg) {
                    // Brand row (top-left logo, top-right status pill).
                    HStack {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(ColorPalette.primaryCyan)
                            Text("ExpresScan")
                                .font(.headline)
                        }
                        Spacer()
                        // Placeholder pill — E-app-wire flips this to
                        // reflect SSE state (Online / Connecting / Offline).
                        StatusPill(
                            label: "Ready",
                            systemImage: "checkmark.circle.fill",
                            tone: .positive
                        )
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.md)

                    Spacer()

                    // Hero: animated NFC glyph + label.
                    VStack(spacing: Spacing.lg) {
                        AnimatedNFCGlyph(
                            size: 96,
                            tint: ColorPalette.primaryCyan,
                            cycle: 0.8
                        )
                        Text("Ready to Scan")
                            .font(.largeTitle.weight(.bold))
                        Text("Wait for a charging station or admin to start a scan.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.lg)
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
                        Button(role: .destructive) {
                            // E-app-wire wires the real DELETE call.
                            // Skeleton: clear keychain + return home.
                            Task {
                                try? await app.authStore.deleteAll()
                                coordinator.didSignOut()
                            }
                        } label: {
                            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.forward")
                                .font(.callout)
                                .foregroundStyle(ColorPalette.destructiveRose)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.lg)
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
                    .environment(coordinator)
            }
        }
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
