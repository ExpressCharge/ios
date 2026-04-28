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
//  K3a: a hidden 5-tap-on-top-left-corner gesture surfaces the
//  Diagnostics sheet. This is **not** a security control — kiosk is
//  UX simplification, not lockdown. Documented in `60-security.md`
//  addendum. Without this escape valve a kiosked iPad whose web admin
//  is unreachable would be bricked from the operator's POV.
//

import SwiftUI

/// Chrome-stripped wrapper for kiosk mode. Hides the toolbar,
/// persistent system overlays, and the status bar. Layers an
/// invisible 60×60pt corner tap-target that opens Diagnostics on five
/// rapid taps — the on-device escape valve.
public struct KioskShell<Content: View>: View {

    private let content: Content

    /// Top-left corner zone size for the escape gesture. ~60pt is
    /// large enough to hit reliably with 5 finger-taps but small
    /// enough to never get hit accidentally during normal use.
    private static var escapeZoneSide: CGFloat { 60 }

    @State private var isShowingDiagnostics: Bool = false

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .toolbar(.hidden, for: .navigationBar, .tabBar)
            .persistentSystemOverlays(.hidden)
            .statusBarHidden(true)
            .overlay(alignment: .topLeading) {
                Color.clear
                    .frame(
                        width: Self.escapeZoneSide,
                        height: Self.escapeZoneSide
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: 5) {
                        isShowingDiagnostics = true
                    }
                    .accessibilityHidden(true)
            }
            .sheet(isPresented: $isShowingDiagnostics) {
                DiagnosticsSheet()
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.thinMaterial)
                    .presentationCornerRadius(32)
            }
    }
}
