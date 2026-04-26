//
//  ExpresScanTests.swift
//  ExpresScanTests
//
//  Placeholder app-target test bundle so xcodegen has somewhere to
//  attach a test target on the developer Mac. The bundle itself imports
//  `@testable import ExpresScan` — that depends on the `ExpresScan`
//  framework target which is defined by `project.yml`. Real tests for
//  the app-target services (`ScanCoordinator`, `EventStreamReconnector`,
//  `ScanResultQueue`, etc.) land here once the project compiles for
//  the first time on a Mac.
//
//  The pure-Swift libraries in `Sources/` already have full coverage in
//  `Tests/ModelsTests`, `Tests/CryptoTests`, `Tests/NetworkingTests`,
//  `Tests/AuthCoreTests`. Those run from `swift test` (or
//  `scripts/swift-test.sh`) on any host.
//

import XCTest

@testable import ExpresScan

final class ExpresScanTests: XCTestCase {

    /// Sanity check: the app-target builds and links against the
    /// `Networking` / `Models` / `Crypto` / `AuthCore` libraries.
    func testTargetIsLinked() {
        // The bundle has at least one symbol; if `@testable import
        // ExpresScan` resolved, this passes.
        XCTAssertTrue(true, "App-target test bundle linked.")
    }
}
