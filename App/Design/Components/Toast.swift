//
//  Toast.swift
//  ExpresScan
//
//  Reusable bottom-anchored toast extracted from the diagnostics-sheet
//  copy-toast pattern. Apply via the `.toast(_:duration:)` modifier with
//  a `Binding<String?>` — non-nil shows, nil hides. Auto-dismisses after
//  `duration` seconds; the dismissal task is cancelled and rescheduled
//  whenever the message changes.
//

import SwiftUI

public struct ToastConfiguration: Sendable, Equatable {
    public let message: String
    public init(message: String) {
        self.message = message
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var message: String?
    let duration: TimeInterval

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    Text(message)
                        .font(.callout)
                        .padding(Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .padding(.bottom, Spacing.lg)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: message)
            .task(id: message) {
                guard message != nil else { return }
                let nanos = UInt64(duration * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                if !Task.isCancelled {
                    message = nil
                }
            }
    }
}

extension View {
    /// Bottom-anchored toast that fades in/out using `.ultraThinMaterial`
    /// and `Radius.md`. Auto-dismisses after `duration`. Pass `nil` to
    /// hide. Mirrors the diagnostics-sheet copy-toast pattern.
    public func toast(
        _ message: Binding<String?>,
        duration: TimeInterval = 2.0
    ) -> some View {
        modifier(ToastModifier(message: message, duration: duration))
    }
}
