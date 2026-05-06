//
//  EventStreamReconnectorTests.swift
//  ExpresScanTests
//
//  Tests the backoff/jitter math driving SSE reconnects. The actual
//  network loop is exercised end-to-end against the real backend on
//  the developer-Mac milestone — these unit tests just pin down the
//  delay schedule so a future refactor can't silently make the client
//  hammer the server.
//
//  Spec: `50-ios.md` § "SSE client" → "Reconnect backoff".
//

import XCTest

@testable import ExpresScan

@MainActor
final class EventStreamReconnectorTests: XCTestCase {

    func testBackoffScheduleMatchesSpec() {
        // Documented schedule: 1, 2, 4, 8, 30 seconds.
        XCTAssertEqual(
            EventStreamReconnector.backoffSchedule,
            [1, 2, 4, 8, 30]
        )
    }

    func testJitterFractionStaysAt25Percent() {
        // The reconnect plan only tolerates a small jitter window;
        // bumping this too high would make the reconnect-count count
        // diverge wildly across runs.
        XCTAssertEqual(EventStreamReconnector.jitterFraction, 0.25, accuracy: 1e-6)
    }

    func testFirstAttemptIsRoughlyOneSecond() {
        // attempt = 0 → base 1s, ±25% jitter → [0.75 ... 1.25].
        let reconnector = makeReconnector()
        for _ in 0..<20 {
            let delay = reconnector.nextDelay()
            XCTAssertGreaterThanOrEqual(delay, 0.75)
            XCTAssertLessThanOrEqual(delay, 1.25)
        }
    }

    func testDelayNeverGoesBelowFloor() {
        // The implementation guards against underflow with `max(0.1, ...)`.
        // We can't easily set a negative attempt, but at the 30s tier
        // jitter can't push it below 22.5s anyway. Just confirm we
        // always return a positive number.
        let reconnector = makeReconnector()
        for _ in 0..<50 {
            XCTAssertGreaterThan(reconnector.nextDelay(), 0)
        }
    }

    // MARK: - Helpers

    private func makeReconnector() -> EventStreamReconnector {
        EventStreamReconnector(environment: AppEnvironment.shared)
    }
}
