//
//  RootCoordinatorTests.swift
//  ExpresScanTests
//
//  Tests the auth-gate router's transition table.
//
//  Spec: `50-ios.md` § "Welcome / login flow".
//

import XCTest

@testable import ExpresScan

@MainActor
final class RootCoordinatorTests: XCTestCase {

    func testInitialRouteIsLaunching() {
        let coordinator = RootCoordinator()
        XCTAssertEqual(coordinator.route, .launching)
    }

    func testStartLoginMovesToLoggingIn() {
        let coordinator = RootCoordinator()
        coordinator.startLogin()
        XCTAssertEqual(coordinator.route, .loggingIn)
    }

    func testCancelLoginReturnsToWelcome() {
        let coordinator = RootCoordinator()
        coordinator.startLogin()
        coordinator.cancelLogin()
        XCTAssertEqual(coordinator.route, .welcome)
    }

    func testReceivingOneTimeCodeMovesToRegistering() {
        let coordinator = RootCoordinator()
        coordinator.startLogin()
        coordinator.didReceiveOneTimeCode("ot_abc", codeVerifier: "v_xyz")
        if case .registering(let code, let verifier) = coordinator.route {
            XCTAssertEqual(code, "ot_abc")
            XCTAssertEqual(verifier, "v_xyz")
        } else {
            XCTFail("Expected .registering, got \(coordinator.route)")
        }
    }

    func testCompletingRegistrationMovesToPriming() {
        let coordinator = RootCoordinator()
        coordinator.didReceiveOneTimeCode("c", codeVerifier: "v")
        coordinator.didCompleteRegistration()
        XCTAssertEqual(coordinator.route, .priming)
    }

    func testSignOutTeardownClearsScanCoordinatorAndReturnsToWelcome() {
        let coordinator = RootCoordinator()
        // Synthesise a "signed-in" state by attaching a scan coordinator.
        let scan = coordinator.ensureScanCoordinator(environment: AppEnvironment.shared)
        XCTAssertNotNil(coordinator.scan)
        XCTAssertTrue(coordinator.scan === scan)

        coordinator.didSignOut()
        XCTAssertNil(coordinator.scan)
        XCTAssertEqual(coordinator.route, .welcome)
    }

    func testEnsureScanCoordinatorIsIdempotent() {
        let coordinator = RootCoordinator()
        let a = coordinator.ensureScanCoordinator(environment: AppEnvironment.shared)
        let b = coordinator.ensureScanCoordinator(environment: AppEnvironment.shared)
        // Same instance — we never want a second SSE/heartbeat pair to
        // race the first one for the same session.
        XCTAssertTrue(a === b)
    }
}
