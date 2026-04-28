//
//  MainTabContainerViewModelTests.swift
//  ExpresScanTests
//
//  Wave 6 / Slice F. Asserts that the capability-derived shell decision
//  matches the legality + visibility table from `docs/plan/...` (the
//  iOS shell Combinations table).
//

import XCTest
@testable import ExpresScan
import Capabilities
import Models

@MainActor
final class MainTabContainerViewModelTests: XCTestCase {

    // MARK: - Combinations table

    func testScannerOnly_isLoneScan() {
        let vm = MainTabContainerViewModel(capabilities: [.scanner])
        XCTAssertEqual(vm.shell, .loneScan)
        XCTAssertFalse(vm.tabBarVisible)
        XCTAssertTrue(vm.settingsMenuVisible)
    }

    func testUserOnly_isLoneChargers() {
        let vm = MainTabContainerViewModel(capabilities: [.user])
        XCTAssertEqual(vm.shell, .loneChargers)
        XCTAssertFalse(vm.tabBarVisible)
        XCTAssertTrue(vm.settingsMenuVisible)
    }

    func testScannerAndUser_isTabs() {
        let vm = MainTabContainerViewModel(capabilities: [.scanner, .user])
        XCTAssertEqual(vm.shell, .tabs)
        XCTAssertTrue(vm.tabBarVisible)
        XCTAssertTrue(vm.settingsMenuVisible)
    }

    func testKioskScanner_isKioskScan() {
        let vm = MainTabContainerViewModel(capabilities: [.kiosk, .scanner])
        XCTAssertEqual(vm.shell, .kioskScan)
        XCTAssertFalse(vm.tabBarVisible)
        XCTAssertFalse(vm.settingsMenuVisible)
    }

    func testKioskUser_isKioskChargers() {
        let vm = MainTabContainerViewModel(capabilities: [.kiosk, .user])
        XCTAssertEqual(vm.shell, .kioskChargers)
        XCTAssertFalse(vm.tabBarVisible)
        XCTAssertFalse(vm.settingsMenuVisible)
    }

    // MARK: - Tab-bar visibility precise rule

    func testTabBarVisible_iff_scannerAndUser() {
        let cases: [(Set<DeviceCapability>, Bool)] = [
            ([],                            false),
            ([.scanner],                    false),
            ([.user],                       false),
            ([.scanner, .user],             true),
            ([.scanner, .kiosk],            false),
            ([.user, .kiosk],               false),
            ([.scanner, .user, .kiosk],     true), // illegal but logic-only
        ]
        for (caps, expected) in cases {
            let vm = MainTabContainerViewModel(capabilities: caps)
            XCTAssertEqual(
                vm.tabBarVisible, expected,
                "tabBarVisible for \(caps) expected \(expected)"
            )
        }
    }

    // MARK: - Legality (kiosk constraint)

    func testKioskWithoutBaseCap_isIllegal() {
        // Kiosk requires exactly one of {scanner, user} alongside.
        XCTAssertFalse(DeviceCapability.isLegalSet([.kiosk]))
        XCTAssertFalse(DeviceCapability.isLegalSet([.kiosk, .scanner, .user]))
        XCTAssertTrue(DeviceCapability.isLegalSet([.kiosk, .scanner]))
        XCTAssertTrue(DeviceCapability.isLegalSet([.kiosk, .user]))
    }

    func testNonKioskSetsAreLegal() {
        XCTAssertTrue(DeviceCapability.isLegalSet([]))
        XCTAssertTrue(DeviceCapability.isLegalSet([.scanner]))
        XCTAssertTrue(DeviceCapability.isLegalSet([.user]))
        XCTAssertTrue(DeviceCapability.isLegalSet([.scanner, .user]))
    }

    // MARK: - Capability mutation reflows shell

    func testMutatingCapabilitiesReflows() {
        let vm = MainTabContainerViewModel(capabilities: [.scanner])
        XCTAssertEqual(vm.shell, .loneScan)
        vm.capabilities = [.scanner, .user]
        XCTAssertEqual(vm.shell, .tabs)
        vm.capabilities = [.user, .kiosk]
        XCTAssertEqual(vm.shell, .kioskChargers)
    }
}
