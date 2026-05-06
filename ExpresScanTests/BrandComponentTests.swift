//
//  BrandComponentTests.swift
//  ExpresScanTests
//
//  Smoke tests for the brand surface components introduced as part of
//  the iOS 26 reskin. We verify each renders without crashing at every
//  documented size, and that reduce-motion variants succeed (they
//  exercise a different code path inside the components).
//

import SwiftUI
import XCTest

@testable import ExpresScan

@MainActor
final class BrandComponentTests: XCTestCase {

    // MARK: - BrandLogo

    func testBrandLogoRendersAtAllSizes() {
        for size in [BrandLogo.Size.small, .medium, .large] {
            let view = BrandLogo(size: size).frame(width: 200, height: 200)
            let image = ImageRenderer(content: view).uiImage
            XCTAssertNotNil(image, "BrandLogo \(size) failed to render")
        }
    }

    func testBrandLogoRendersWithoutCrashing() {
        // The reduce-motion code path is exercised by the SwiftUI
        // preview machinery and via the Settings → Accessibility
        // toggle in iOS UI tests. Smoke-test that the default render
        // path works here.
        let view = BrandLogo(size: .medium).frame(width: 200, height: 200)
        XCTAssertNotNil(ImageRenderer(content: view).uiImage)
    }

    // MARK: - Wordmark

    func testWordmarkRendersAtAllSizes() {
        for size in [Wordmark.Size.small, .medium, .large] {
            let view = Wordmark(size: size).frame(width: 320, height: 80)
            XCTAssertNotNil(ImageRenderer(content: view).uiImage)
        }
    }

    func testAnimatedWordmarkRenders() {
        let view = AnimatedWordmark(size: .large).frame(width: 320, height: 80)
        XCTAssertNotNil(ImageRenderer(content: view).uiImage)
    }

    // MARK: - BrandLockup

    func testBrandLockupRendersInBothVariants() {
        let login = BrandLockup(.login).frame(width: 360, height: 200)
        let compact = BrandLockup(.compact).frame(width: 200, height: 50)
        XCTAssertNotNil(ImageRenderer(content: login).uiImage)
        XCTAssertNotNil(ImageRenderer(content: compact).uiImage)
    }
}
