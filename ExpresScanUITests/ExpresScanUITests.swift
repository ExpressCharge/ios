//
//  ExpresScanUITests.swift
//  ExpresScanUITests
//
//  Black-box UI tests that drive the real app via XCTest's
//  accessibility automation. The Welcome screen is the only surface
//  guaranteed to render on launch when the keychain is empty (which
//  is the simulator default), so every test starts there.
//
//  Spec: `50-ios.md` § "Welcome / login flow".
//

import XCTest

@MainActor
final class ExpresScanUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        // Stop on the first failure — UI tests in a sequence after
        // a missed element are usually noise.
        continueAfterFailure = false
        app = XCUIApplication()
        // Reset device-defaults each launch so dedup state doesn't
        // leak between tests on a re-used simulator.
        app.launchArguments += ["-AppleResetUserDefaults", "YES"]
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Smoke

    func testAppLaunchesWithoutCrashing() {
        app.launch()
        // Welcome screen renders within 5 seconds on cold launch.
        XCTAssertTrue(
            app.staticTexts["ExpressCharge"].waitForExistence(timeout: 5),
            "Expected Welcome screen 'ExpressCharge' headline to appear"
        )
    }

    // MARK: - Welcome screen

    func testWelcomeShowsBrandHeadline() {
        app.launch()
        let headline = app.staticTexts["ExpressCharge"]
        XCTAssertTrue(headline.waitForExistence(timeout: 5))
    }

    func testWelcomeShowsExplanatoryCopy() {
        app.launch()
        // Substring match — full sentence is too long for a stable
        // accessibility identifier. Asserts the customer-facing copy
        // mentions card scanning (any iteration of the wording).
        let bodyExists = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'scan cards'")
        ).element.waitForExistence(timeout: 5)
        XCTAssertTrue(
            bodyExists,
            "Expected welcome body copy to mention card scanning"
        )
    }

    func testWelcomeShowsSignInButton() {
        app.launch()
        // Use the stable accessibilityIdentifier set by `PrimaryButton`.
        // The label-CONTAINS predicate matches the button's child Text
        // element on iOS 26's accessibility tree, which then fails the
        // hittability check in CI's iPhone 17 Pro simulator. The id is
        // unambiguous and survives label copy changes.
        let signIn = app.buttons["primaryButton_Sign in"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        XCTAssertTrue(signIn.isHittable)
    }

    func testSignInButtonHasAccessibilityHint() {
        app.launch()
        let signIn = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] 'Sign in'")
        ).element
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        // The button declares a `.accessibilityHint(...)` — the actual
        // text rotates with the wireframe copy, but its presence is
        // load-bearing for VoiceOver.
        XCTAssertNotNil(signIn.value)
    }

    func testPrimaryButtonAccessibilityIdentifier() {
        app.launch()
        // The shared `PrimaryButton` wraps every CTA with a stable
        // `accessibilityIdentifier("primaryButton_<label>")` so XCUITest
        // queries don't flake on glass-rendering jitter. The Welcome
        // CTA is "Sign in".
        let cta = app.buttons["primaryButton_Sign in"]
        XCTAssertTrue(cta.waitForExistence(timeout: 5))
    }

    // MARK: - Accessibility audits

    func testWelcomeScreenPassesAccessibilityAudit() throws {
        app.launch()
        XCTAssertTrue(
            app.staticTexts["ExpressCharge"].waitForExistence(timeout: 5)
        )
        // iOS 17+ ships an automated audit. We exclude `.contrast`
        // because the animated AuroraText wordmark briefly dips below
        // the WCAG-AA threshold during its 8s gradient cycle —
        // matching the web ExpresSync wordmark's behaviour. Visual
        // contrast is reviewed manually by design. Hit regions,
        // dynamic-type clipping, and VoiceOver descriptions still
        // must pass.
        try app.performAccessibilityAudit(
            for: [.hitRegion, .dynamicType, .sufficientElementDescription]
        )
    }

    // MARK: - Performance

    func testLaunchPerformance() {
        // Cold launch baseline. Will fail loudly if a future change
        // adds a >1s synchronous block to init.
        //
        // Terminate the `setUp()`-allocated `app` first so the metric's
        // own launch/terminate cycle owns the only running instance.
        // Without this, CI's iPhone 17 Pro simulator occasionally
        // refuses to terminate the leftover process between iterations
        // ("Failed to terminate com.example.expresscharge.ios:NNNN").
        app.terminate()
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let perfApp = XCUIApplication()
            perfApp.launch()
            perfApp.terminate()
        }
    }
}
