//
//  PushServiceTests.swift
//  ExpresScanTests
//
//  Unit tests for `PushService.decodeScanRequest(from:)`. The pure
//  decoding helper is exercised here so we don't need to spin up an
//  `AppEnvironment` / `ScanCoordinator` to verify payload shapes.
//
//  Spec: `20-contracts.md` § "APNs payload (canonical)"
//

import XCTest
@testable import ExpresScan
import Models

final class PushServiceTests: XCTestCase {

    // MARK: - Happy path

    func testDecodesCompletePayload() {
        let userInfo: [AnyHashable: Any] = [
            "deviceId": "dev_abc",
            "pairingCode": "pair_xyz",
            "purpose": "admin-link",
            "expiresAtEpochMs": NSNumber(value: 1_700_000_000_000),
            "expiresAtIso": "2023-11-14T22:13:20Z",
            "hintLabel": "Front desk",
            "requestedByUserId": "usr_42",
        ]

        let request = PushService.decodeScanRequest(from: userInfo)

        XCTAssertEqual(request?.deviceId, "dev_abc")
        XCTAssertEqual(request?.pairingCode, "pair_xyz")
        XCTAssertEqual(request?.purpose, .adminLink)
        XCTAssertEqual(request?.expiresAtEpochMs, 1_700_000_000_000)
        XCTAssertEqual(request?.expiresAtIso, "2023-11-14T22:13:20Z")
        XCTAssertEqual(request?.hintLabel, "Front desk")
        XCTAssertEqual(request?.requestedByUserId, "usr_42")
    }

    // MARK: - Number / string flexibility on `expiresAtEpochMs`

    func testDecodesEpochMsAsString() {
        let userInfo: [AnyHashable: Any] = [
            "deviceId": "dev_abc",
            "pairingCode": "pair_xyz",
            "purpose": "login",
            "expiresAtEpochMs": "1700000000000",
        ]
        let request = PushService.decodeScanRequest(from: userInfo)
        XCTAssertEqual(request?.expiresAtEpochMs, 1_700_000_000_000)
    }

    func testRejectsUnparseableEpochMsString() {
        let userInfo: [AnyHashable: Any] = [
            "deviceId": "dev_abc",
            "pairingCode": "pair_xyz",
            "purpose": "login",
            "expiresAtEpochMs": "not_a_number",
        ]
        XCTAssertNil(PushService.decodeScanRequest(from: userInfo))
    }

    // MARK: - Missing fields → nil

    func testReturnsNilWhenDeviceIdMissing() {
        let userInfo: [AnyHashable: Any] = [
            "pairingCode": "pair_xyz",
            "purpose": "admin-link",
            "expiresAtEpochMs": NSNumber(value: 1),
        ]
        XCTAssertNil(PushService.decodeScanRequest(from: userInfo))
    }

    func testReturnsNilWhenPairingCodeMissing() {
        let userInfo: [AnyHashable: Any] = [
            "deviceId": "dev_abc",
            "purpose": "admin-link",
            "expiresAtEpochMs": NSNumber(value: 1),
        ]
        XCTAssertNil(PushService.decodeScanRequest(from: userInfo))
    }

    func testReturnsNilWhenPurposeUnknown() {
        let userInfo: [AnyHashable: Any] = [
            "deviceId": "dev_abc",
            "pairingCode": "pair_xyz",
            "purpose": "unsupported_kind",
            "expiresAtEpochMs": NSNumber(value: 1),
        ]
        XCTAssertNil(PushService.decodeScanRequest(from: userInfo))
    }

    func testReturnsNilWhenEpochMsMissing() {
        let userInfo: [AnyHashable: Any] = [
            "deviceId": "dev_abc",
            "pairingCode": "pair_xyz",
            "purpose": "admin-link",
        ]
        XCTAssertNil(PushService.decodeScanRequest(from: userInfo))
    }

    // MARK: - Optional fields

    func testOptionalFieldsCanBeMissing() {
        let userInfo: [AnyHashable: Any] = [
            "deviceId": "dev_abc",
            "pairingCode": "pair_xyz",
            "purpose": "view-card",
            "expiresAtEpochMs": NSNumber(value: 1_700_000_000_000),
        ]
        let request = PushService.decodeScanRequest(from: userInfo)
        XCTAssertNotNil(request)
        XCTAssertNil(request?.hintLabel)
        XCTAssertNil(request?.requestedByUserId)
    }

    func testSynthesisesIsoFromEpochMsWhenAbsent() {
        let userInfo: [AnyHashable: Any] = [
            "deviceId": "dev_abc",
            "pairingCode": "pair_xyz",
            "purpose": "customer-link",
            "expiresAtEpochMs": NSNumber(value: 1_700_000_000_000),
        ]
        let request = PushService.decodeScanRequest(from: userInfo)
        // Should at least be a valid ISO 8601 string.
        XCTAssertNotNil(request?.expiresAtIso)
        XCTAssertTrue(request?.expiresAtIso.contains("2023") ?? false)
    }
}
