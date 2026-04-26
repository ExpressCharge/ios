//
//  ScanActiveView.swift
//  ExpresScan
//
//  Shown when a scan request is armed and waiting for the user to tap
//  a card. Per the wireframes:
//   - Glyph turns green and pulses faster (0.4s).
//   - Countdown ring around the glyph reflects time left.
//   - Dynamic subheading by `ScanPurpose`.
//   - "Tap to scan" button starts the NFCTagReaderSession (E-app-wire).
//   - Cancel returns to Ready.
//
//  Skeleton: layout + bindings only. The actual `NFCTagReaderSession`
//  presentation lives in `NFCService` (E-app-wire).
//
//  Spec: `50-ios.md` § "UX details" → "Scan request".
//

import SwiftUI

import Models

public struct ScanActiveView: View {

    public let request: ScanRequest
    /// 0…1 ring progress; 1 at issuance, 0 at expiry.
    public let progress: Double

    /// Wired by E-app-wire to `NFCService.beginSession(...)` and
    /// `ScanCoordinator.cancelScan()` respectively.
    public let onTapToScan: () -> Void
    public let onCancel: () -> Void

    public init(
        request: ScanRequest,
        progress: Double,
        onTapToScan: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {}
    ) {
        self.request = request
        self.progress = progress
        self.onTapToScan = onTapToScan
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            ColorPalette.background.ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                Spacer()

                ZStack {
                    CountdownRing(progress: progress, lineWidth: 8, tint: ColorPalette.voltGreen)
                        .frame(width: 160, height: 160)
                    AnimatedNFCGlyph(
                        size: 96,
                        tint: ColorPalette.voltGreen,
                        cycle: 0.4
                    )
                }
                .accessibilityLabel("Scan a card now")

                VStack(spacing: Spacing.sm) {
                    Text("Scan a card now")
                        .font(.title.weight(.bold))
                    Text(subheading(for: request))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                }

                if let hint = request.hintLabel {
                    StatusPill(
                        label: hint,
                        systemImage: "tag.fill",
                        tone: .info
                    )
                }

                Spacer()

                VStack(spacing: Spacing.sm) {
                    Button(action: onTapToScan) {
                        Text("Tap to scan")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .foregroundStyle(.white)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                    .fill(ColorPalette.voltGreen)
                            )
                    }
                    .buttonStyle(.plain)

                    Button("Cancel", role: .cancel, action: onCancel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xl)
            }
        }
    }

    private func subheading(for request: ScanRequest) -> String {
        switch request.purpose {
        case .adminLink:
            return "An admin is linking this card to a customer."
        case .customerLink:
            return "Add this card to your account."
        case .login:
            return "Use this card to sign in."
        case .viewCard:
            return "Look up the card's account."
        }
    }
}
