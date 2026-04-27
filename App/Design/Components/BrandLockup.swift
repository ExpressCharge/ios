//
//  BrandLockup.swift
//  ExpresScan
//
//  Composite brand mark: BrandLogo + Wordmark in an HStack. Mirrors the
//  web `ExpresSyncBrand` component's `variant="login"` (large) and
//  `variant="sidebar-expanded"` (compact) configurations.
//

import SwiftUI

public struct BrandLockup: View {

    public enum Variant: Sendable {
        /// Large vertical lockup for splash / login screens.
        case login
        /// Small horizontal lockup for headers and tight rows.
        case compact
    }

    public let variant: Variant

    public init(_ variant: Variant) {
        self.variant = variant
    }

    public var body: some View {
        switch variant {
        case .login:
            VStack(spacing: Spacing.lg) {
                BrandLogo(size: .large)
                AnimatedWordmark(size: .large)
            }
        case .compact:
            HStack(spacing: Spacing.sm) {
                BrandLogo(size: .small)
                Wordmark(size: .medium)
            }
        }
    }
}

#if DEBUG
#Preview("Lockups") {
    VStack(spacing: 48) {
        BrandLockup(.login)
        BrandLockup(.compact)
    }
    .padding()
}
#endif
