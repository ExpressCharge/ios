//
//  CardSurface.swift
//  ExpresScan
//
//  Centralizes the canonical card chrome that's currently duplicated
//  across `ActiveSessionCard`, `ReadyView`, etc. — a continuous-radius
//  rounded rectangle filled with `ColorPalette.card` (or a tone tint)
//  and stroked at 1pt with `borderSubtle` (or a tone-tinted stroke).
//
//  Apply via the `.cardSurface()` view modifier; pick a tone with
//  `.cardSurface(.tinted(.positive))`.
//

import SwiftUI

/// Visual style for `cardSurface(_:radius:padding:)`.
public enum CardSurfaceStyle: Sendable, Equatable {
    /// Neutral card — `ColorPalette.card` fill with `borderSubtle` 1pt stroke.
    case neutral
    /// Tinted card — tone fill at 0.08 opacity with stroke at 0.35.
    case tinted(StatusPill.Tone)
}

/// Maps a `StatusPill.Tone` to its semantic palette color. Mirrors the
/// (file-private) `fillColor` accessor on `StatusPill.Tone` so the modifier
/// can render tinted variants without mutating the public surface area
/// of `StatusPill`.
private func cardSurfaceTint(for tone: StatusPill.Tone) -> Color {
    switch tone {
    case .positive: return ColorPalette.success
    case .warning: return ColorPalette.warningAmber
    case .negative: return ColorPalette.destructiveRose
    case .neutral: return ColorPalette.mutedForeground
    case .info: return ColorPalette.info
    }
}

private struct CardSurfaceModifier: ViewModifier {
    let style: CardSurfaceStyle
    let radius: CGFloat
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 1)
            )
    }

    private var fillColor: Color {
        switch style {
        case .neutral:
            return ColorPalette.card
        case .tinted(let tone):
            return cardSurfaceTint(for: tone).opacity(0.08)
        }
    }

    private var strokeColor: Color {
        switch style {
        case .neutral:
            return ColorPalette.borderSubtle
        case .tinted(let tone):
            return cardSurfaceTint(for: tone).opacity(0.35)
        }
    }
}

extension View {
    /// Applies the canonical ExpresScan card chrome — continuous rounded
    /// rectangle fill + 1pt stroke — and pads the wrapped content.
    public func cardSurface(
        _ style: CardSurfaceStyle = .neutral,
        radius: CGFloat = Radius.lg,
        padding: CGFloat = Spacing.lg
    ) -> some View {
        modifier(CardSurfaceModifier(style: style, radius: radius, padding: padding))
    }
}
