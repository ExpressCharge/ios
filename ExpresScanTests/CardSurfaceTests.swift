//
//  CardSurfaceTests.swift
//  ExpresScanTests
//
//  Render-smoke tests for the design-system primitives `cardSurface`
//  and `SectionHeader`. Mirrors the `PrimaryButtonTests` convention —
//  push the view through `ImageRenderer` and assert it produced a
//  non-empty bitmap. Pixel-level snapshotting lives elsewhere.
//

import SwiftUI
import XCTest

@testable import ExpresScan

@MainActor
final class CardSurfaceTests: XCTestCase {

    func testNeutralCardSurfaceRenders() {
        let view = Text("Neutral")
            .cardSurface(.neutral)
            .frame(width: 320, height: 120)
        let image = ImageRenderer(content: view).uiImage
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
        XCTAssertGreaterThan(image?.size.height ?? 0, 0)
    }

    func testTintedCardSurfaceRendersForEveryTone() {
        for tone: StatusPill.Tone in [.positive, .warning, .negative, .neutral, .info] {
            let view = Text("Tinted")
                .cardSurface(.tinted(tone))
                .frame(width: 320, height: 120)
            let image = ImageRenderer(content: view).uiImage
            XCTAssertNotNil(image, "tinted(\(tone)) failed to render")
            XCTAssertGreaterThan(image?.size.width ?? 0, 0)
        }
    }

    func testSectionHeaderRendersWithAndWithoutTrailing() {
        let plain = SectionHeader("Connection")
            .frame(width: 320, height: 32)
        XCTAssertNotNil(ImageRenderer(content: plain).uiImage)

        let withTrailing = SectionHeader("Connection") {
            StatusPill(label: "Online", systemImage: "checkmark.circle.fill", tone: .positive)
        }
        .frame(width: 320, height: 32)
        let image = ImageRenderer(content: withTrailing).uiImage
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
    }
}
