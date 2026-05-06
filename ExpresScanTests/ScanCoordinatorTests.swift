//
//  ScanCoordinatorTests.swift
//  ExpresScanTests
//
//  Tests the deduplication / coalescing window for incoming scan
//  requests (push and SSE both deliver the same event), and the basic
//  state-machine transitions that don't require the network.
//
//  Spec: `50-ios.md` § "State machine".
//

import Models
import XCTest

@testable import ExpresScan

@MainActor
final class ScanCoordinatorTests: XCTestCase {

    // Shared test clock — start fresh per test.
    private var clock: TestClock!

    override func setUp() async throws {
        try await super.setUp()
        clock = TestClock(start: Date(timeIntervalSince1970: 1_700_000_000))
        // Wipe the persisted dedup cache so the coordinator boots clean.
        UserDefaults.standard.removeObject(forKey: "ExpresScan.RecentPairingsV1")
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "ExpresScan.RecentPairingsV1")
        try await super.tearDown()
    }

    // MARK: - Initial state

    func testInitialStateIsIdle() {
        let scan = makeCoordinator()
        XCTAssertEqual(scan.state, .idle)
        XCTAssertEqual(scan.connectionStatus, .offline)
        XCTAssertNil(scan.armedAt)
        XCTAssertNil(scan.lastHeartbeatAt)
        XCTAssertEqual(scan.reconnectCount, 0)
        XCTAssertEqual(scan.pendingScanResultCount, 0)
    }

    // MARK: - Incoming request → arm

    func testFirstIncomingRequestArmsState() {
        let scan = makeCoordinator()
        let request = makeRequest(pairing: "p1", expiresInSeconds: 60)

        scan.handleIncomingScanRequest(request, source: .push)

        // `handleIncomingScanRequest` arms via `.scanRequested` and
        // then synchronously calls `beginScan()`, which transitions
        // to `.scanning(request)` so the iOS NFC reader sheet fires
        // immediately. Tests assert the post-`beginScan` state.
        if case .scanning(let armed) = scan.state {
            XCTAssertEqual(armed.pairingCode, "p1")
        } else {
            XCTFail("Expected .scanning, got \(scan.state)")
        }
        XCTAssertEqual(scan.armedAt, clock.now())
    }

    func testExpiredRequestGoesStraightToError() {
        let scan = makeCoordinator()
        let request = makeRequest(pairing: "p1", expiresInSeconds: -10)

        scan.handleIncomingScanRequest(request, source: .push)

        XCTAssertEqual(scan.state, .error(.pairingExpired))
        XCTAssertNil(scan.armedAt)
    }

    // MARK: - Dedup window

    func testSecondIncomingForSamePairingIsCoalesced() {
        let scan = makeCoordinator()
        let request = makeRequest(pairing: "p1", expiresInSeconds: 60)

        scan.handleIncomingScanRequest(request, source: .push)
        // Move to .readyToScan to detect re-arm.
        scan.cancelActiveScan()
        XCTAssertEqual(scan.state, .readyToScan)

        // Same pairing arrives again — SHOULD be ignored.
        scan.handleIncomingScanRequest(request, source: .sse)
        XCTAssertEqual(scan.state, .readyToScan)
    }

    func testDifferentPairingIsNotCoalesced() {
        let scan = makeCoordinator()
        let r1 = makeRequest(pairing: "p1", expiresInSeconds: 60)
        let r2 = makeRequest(pairing: "p2", expiresInSeconds: 60)

        scan.handleIncomingScanRequest(r1, source: .push)
        scan.cancelActiveScan()
        scan.handleIncomingScanRequest(r2, source: .sse)

        if case .scanning(let armed) = scan.state {
            XCTAssertEqual(armed.pairingCode, "p2")
        } else {
            XCTFail("Expected .scanning for p2, got \(scan.state)")
        }
    }

    func testDedupExpiresAfter90Seconds() {
        let scan = makeCoordinator()
        let request = makeRequest(pairing: "p1", expiresInSeconds: 1000)

        scan.handleIncomingScanRequest(request, source: .push)
        scan.cancelActiveScan()

        // Advance past the coalesce window.
        clock.advance(by: ScanCoordinator.pairingCoalesceWindow + 1)

        // Same pairing should now re-arm. Re-arm flows through
        // `.scanRequested` straight into `.scanning`, so the
        // observable post-call state is `.scanning`.
        scan.handleIncomingScanRequest(request, source: .sse)
        if case .scanning = scan.state {
            // ok
        } else {
            XCTFail("Expected re-arm after dedup window expired, got \(scan.state)")
        }
    }

    // MARK: - Cancel + dismiss

    func testCancelActiveScanGoesToReady() {
        let scan = makeCoordinator()
        scan.handleIncomingScanRequest(
            makeRequest(pairing: "p1", expiresInSeconds: 60), source: .push)
        scan.cancelActiveScan()
        XCTAssertEqual(scan.state, .readyToScan)
        XCTAssertNil(scan.armedAt)
    }

    func testCancelDoesNothingWhenNotArmed() {
        let scan = makeCoordinator()
        scan.cancelActiveScan()
        XCTAssertEqual(scan.state, .idle)
    }

    // MARK: - Reconnect counter

    func testNoteReconnectAttemptIncrementsCount() {
        let scan = makeCoordinator()
        XCTAssertEqual(scan.reconnectCount, 0)
        scan.noteReconnectAttempt()
        XCTAssertEqual(scan.reconnectCount, 1)
        XCTAssertEqual(scan.connectionStatus, .reconnecting)
    }

    // MARK: - Toast

    func testClearToastWipesValue() {
        let scan = makeCoordinator()
        // We can't synthesise a toast from outside the coordinator, but
        // clearToast() should be a safe no-op when no toast is set.
        scan.clearToast()
        XCTAssertNil(scan.transientToast)
    }

    // MARK: - Helpers

    private func makeCoordinator() -> ScanCoordinator {
        let captured = clock!
        return ScanCoordinator(
            environment: AppEnvironment.shared,
            now: { captured.now() }
        )
    }

    private func makeRequest(pairing: String, expiresInSeconds: TimeInterval) -> ScanRequest {
        let expiry = clock.now().addingTimeInterval(expiresInSeconds)
        let ms = Int64(expiry.timeIntervalSince1970 * 1000)
        let formatter = ISO8601DateFormatter()
        return ScanRequest(
            deviceId: "dev_test",
            pairingCode: pairing,
            purpose: .login,
            expiresAtIso: formatter.string(from: expiry),
            expiresAtEpochMs: ms,
            requestedByUserId: nil,
            hintLabel: nil
        )
    }
}

/// Tiny manual clock so tests can fast-forward without `Task.sleep`.
final class TestClock: @unchecked Sendable {
    private var current: Date
    private let lock = NSLock()

    init(start: Date) { self.current = start }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(interval)
    }
}
