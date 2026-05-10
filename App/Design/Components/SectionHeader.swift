//
//  SectionHeader.swift
//  ExpresScan
//
//  Small uppercased label used to title sections in the redesigned
//  Settings/Diagnostics surfaces. Mirrors the iOS Settings list-section
//  convention: subheadline weight semibold, mutedForeground tint,
//  uppercased, with optional trailing slot for inline status.
//

import SwiftUI

public struct SectionHeader<Trailing: View>: View {

    private let title: String
    private let trailing: Trailing

    public init(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(ColorPalette.mutedForeground)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing
        }
        // No horizontal padding — every consumer is already inside a
        // padded card surface (`.cardSurface()` applies Spacing.lg).
        // Per 2026-05 UX feedback, the prior horizontal padding here
        // produced a visible offset that didn't align with the rest of
        // the card body.
    }
}

extension SectionHeader where Trailing == EmptyView {
    /// Convenience initializer for the no-trailing case.
    public init(_ title: String) {
        self.init(title, trailing: { EmptyView() })
    }
}
