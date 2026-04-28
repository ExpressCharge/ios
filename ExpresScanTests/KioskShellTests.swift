//
//  KioskShellTests.swift
//  ExpresScanTests
//
//  Wave 6 / Slice F. Light smoke check that `KioskShell` instantiates
//  with arbitrary content. Full UI assertions (toolbar hidden, status
//  bar hidden) are deferred to slice K's UI tests.
//

import XCTest
import SwiftUI
@testable import ExpresScan

@MainActor
final class KioskShellTests: XCTestCase {

    func testKioskShellWrapsContent() {
        let shell = KioskShell {
            Text("kiosked")
        }
        // Instantiation without crash is the signal here. The chrome
        // modifiers (`.toolbar(.hidden)`, `.persistentSystemOverlays`,
        // `.statusBarHidden(true)`) are SwiftUI view modifiers — their
        // runtime effect is verified in slice K's UI tests.
        let body = shell.body
        XCTAssertNotNil(body)
    }
}
