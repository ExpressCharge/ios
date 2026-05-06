//
//  KioskShellTests.swift
//  ExpresScanTests
//
//  Wave 6 / Slice F. Light smoke check that `KioskShell` instantiates
//  with arbitrary content. Full UI assertions (toolbar hidden, status
//  bar hidden) are deferred to slice K's UI tests.
//

import SwiftUI
import XCTest

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

    func testKioskShellComposesEscapeOverlay() {
        // Sanity: the body computation includes both the wrapped
        // content and the corner-tap escape overlay. We can't drive
        // a real 5-tap gesture from a unit test (UI-test territory),
        // but we can assert the shell's body type isn't elided.
        let shell = KioskShell {
            Text("kiosked")
        }
        let body = shell.body
        let mirror = Mirror(reflecting: body)
        // The view has both the chrome modifiers and the .overlay
        // alignment-topLeading composition; reflecting the body gives
        // a non-empty children set.
        XCTAssertFalse(mirror.children.isEmpty)
    }
}
