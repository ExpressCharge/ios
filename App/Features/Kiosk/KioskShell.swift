//
//  KioskShell.swift
//  ExpresScan
//
//  Wave 6 / Slice F + K3. Generic chrome-stripped wrapper used when
//  `kiosk ∈ capabilities`. Hides the navigation toolbar, persistent
//  system overlays (volume HUD, etc.), and the status bar so a kiosked
//  iPad/iPhone presents only the lone capability's screen.
//
//  Sign-out is impossible from the device under kiosk — the only path
//  is web-admin remote-deregister.
//
//  K3a: a hidden 5-tap-on-top-right-corner gesture surfaces a sheet
//  containing `SettingsView`. The corner is the same place an
//  unkiosked screen renders the Settings toolbar gear, so the escape
//  reuses muscle memory rather than introducing a new affordance. The
//  sheet itself is the standard Settings UI (Diagnostics is reachable
//  from inside Settings → Connectivity → Diagnostics).
//
//  This is **not** a security control — kiosk is UX simplification,
//  not lockdown. Documented in `60-security.md` addendum. Without
//  this escape valve a kiosked iPad whose web admin is unreachable
//  would be bricked from the operator's POV.
//

import SwiftUI
import UIKit

/// Chrome-stripped wrapper for kiosk mode. Hides the toolbar,
/// persistent system overlays, and the status bar. Layers an
/// invisible top-right corner tap-target that opens Settings on five
/// rapid taps — the on-device escape valve.
public struct KioskShell<Content: View>: View {

    private let content: Content

    /// Top-right corner zone size for the escape gesture. Big enough
    /// to land 5 finger-taps reliably without micro-aiming.
    private static var escapeZoneSide: CGFloat { 96 }

    /// Inset from the top edge so the zone clears iOS's reserved
    /// system-gesture strip at the very top of the screen (pulldown
    /// control-center / notification-center area). Without this, the
    /// first tap or two would be eaten by the system.
    private static var topInset: CGFloat { 20 }

    /// Number of taps required to surface the escape sheet.
    private static var requiredTaps: Int { 5 }

    /// Window in which taps must accumulate. Resets the counter when
    /// the user pauses — so a stray tap during normal use doesn't
    /// half-arm the escape.
    private static var resetWindow: TimeInterval { 2.0 }

    @State private var isShowingSettings: Bool = false
    @State private var tapCount: Int = 0
    @State private var resetTask: Task<Void, Never>?

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .toolbar(.hidden, for: .navigationBar, .tabBar)
            .persistentSystemOverlays(.hidden)
            .statusBarHidden(true)
            .overlay(alignment: .topTrailing) {
                // A near-zero-alpha fill keeps the overlay
                // hit-testable on every iOS version (`Color.clear`
                // can opt out of hit testing in some contexts).
                Rectangle()
                    .fill(Color.black.opacity(0.001))
                    .frame(
                        width: Self.escapeZoneSide,
                        height: Self.escapeZoneSide
                    )
                    .contentShape(Rectangle())
                    // High-priority single-tap gesture wins over any
                    // tap recognizer the wrapped content might hold.
                    // We count up to `requiredTaps` ourselves so the
                    // sheet can be triggered without the recognizer
                    // having to coalesce 5 taps into one event.
                    .highPriorityGesture(
                        TapGesture(count: 1).onEnded {
                            handleTap()
                        }
                    )
                    .padding(.top, Self.topInset)
                    .padding(.trailing, 4)
                    .accessibilityHidden(true)
            }
            .sheet(isPresented: $isShowingSettings) {
                // Settings expects a NavigationStack ancestor so its
                // toolbar back-button + Diagnostics push render
                // correctly. Wrap the sheet's contents in one.
                NavigationStack {
                    SettingsView()
                }
                .presentationDetents([.large])
                .presentationBackground(.thinMaterial)
                .presentationCornerRadius(32)
            }
    }

    /// Per-tap state machine. Each tap fires a light haptic so the
    /// operator gets confirmation the zone is registering, and a
    /// trailing reset timer clears the counter if the user pauses.
    private func handleTap() {
        tapCount += 1

        // Light haptic on each accumulating tap; success haptic on
        // the final tap that opens the sheet.
        if tapCount >= Self.requiredTaps {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            tapCount = 0
            resetTask?.cancel()
            resetTask = nil
            isShowingSettings = true
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Reset the counter after a pause so a stray accidental tap
        // during normal use doesn't get the user one tap closer to
        // the escape on subsequent days.
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.resetWindow))
            if !Task.isCancelled {
                tapCount = 0
            }
        }
    }
}
