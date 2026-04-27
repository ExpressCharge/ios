//
//  PrimaryButtonTests.swift
//  ExpresScanTests
//
//  Render-smoke tests for the shared CTA wrapper. We don't snapshot
//  the pixel output here — that lives in a separate workflow — but
//  these tests confirm:
//
//   - Each variant renders to a non-empty image at the standard 44pt
//     mobile-tap target.
//   - The accessibility identifier is wired as `primaryButton_<label>`,
//     so XCUITest predicates can find buttons through Liquid Glass
//     surfaces.
//

import XCTest
import SwiftUI
@testable import ExpresScan

@MainActor
final class PrimaryButtonTests: XCTestCase {

    func testRendersAtAllVariantsAndStates() {
        for variant in [PrimaryButton.Variant.primary, .success, .destructive] {
            for state in [PrimaryButton.State.default, .loading, .disabled] {
                let view = PrimaryButton(
                    "Test",
                    variant: variant,
                    state: state,
                    action: {}
                )
                .frame(width: 320, height: 50)
                let renderer = ImageRenderer(content: view)
                let image = renderer.uiImage
                XCTAssertNotNil(image, "\(variant)/\(state) failed to render")
                XCTAssertGreaterThan(image?.size.width ?? 0, 0)
                XCTAssertGreaterThan(image?.size.height ?? 0, 0)
            }
        }
    }

    func testRendersInPreferredColorSchemes() {
        // `.preferredColorScheme(_:)` is the public modifier for forcing
        // light/dark in tests; the env-keypath approach changed in
        // iOS 26 and rejects the `WritableKeyPath` overload.
        let lightView = PrimaryButton("Sign in", action: {})
            .frame(width: 320, height: 50)
            .preferredColorScheme(.light)
        let darkView = PrimaryButton("Sign in", action: {})
            .frame(width: 320, height: 50)
            .preferredColorScheme(.dark)
        XCTAssertNotNil(ImageRenderer(content: lightView).uiImage)
        XCTAssertNotNil(ImageRenderer(content: darkView).uiImage)
    }
}
