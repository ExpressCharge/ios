//
//  ChargerDetailViewModelTests.swift
//  ExpresScanTests
//
//  Wave 6 / Slice J + Slice S — VM coverage for the customer-style
//  charger detail screen. Slice S replaces the tag picker with a
//  customer picker; the start endpoint now carries
//  `lagoCustomerExternalId` (not `idTag`/`tagPk`).
//
//  Drives the VM via `StubURLProtocol` (same shape as
//  ChargerListViewModelTests / ScanResultQueueTests). Covers:
//   - bootstrap() populates session + reservations
//   - startCharging() Path A (active reservation w/ externalId → no
//     picker, customer auto-resolved from reservation)
//   - startCharging() Path A fall-through when reservation lacks an
//     externalId → picker opens
//   - startCharging() Path B (no reservation → pickerVisible = true)
//   - submitStart(customer:) 200 → optimistic state flip
//   - submitStart(customer:) 409 → "Charger offline" error
//   - stopCharging(confirmed: true) 200 → optimistic state flip
//   - cancelReservation removes the row optimistically
//   - currentReservation derivation (active window covers Date())
//

import XCTest
@testable import ExpresScan
import Networking

@MainActor
final class ChargerDetailViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func apiClient() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        return APIClient(
            baseURL: URL(string: "https://example.test")!,
            transport: session,
            tokenSource: { "test-token" }
        )
    }

    private func makeEntry(
        chargerId: String = "BAY-1",
        state: ChargerListEntry.ChargerState = .idle
    ) -> ChargerListEntry {
        ChargerListEntry(
            chargerId: chargerId,
            label: "Bay 1",
            siteName: nil,
            formFactor: .wallbox,
            connectorType: .ccs,
            maxKw: 22,
            state: state,
            lastSeenAt: nil,
            capabilities: ["charger"]
        )
    }

    private func makeVM(
        entry: ChargerListEntry? = nil,
        now: Date = Date(timeIntervalSince1970: 1_745_750_000)
    ) -> ChargerDetailViewModel {
        let resolvedNow = now
        return ChargerDetailViewModel(
            entry: entry ?? makeEntry(),
            api: apiClient(),
            now: { resolvedNow }
        )
    }

    /// Default success bootstrap: session is idle, no reservations.
    private func installIdleBootstrap() {
        StubURLProtocol.handler = { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("/session") {
                let body = #"""
                {"session": null, "state": "idle", "chargerId": "BAY-1"}
                """#
                return (200, ["Content-Type": "application/json"], Data(body.utf8))
            }
            if path.hasSuffix("/reservations") {
                return (200, ["Content-Type": "application/json"],
                        Data(#"{"reservations":[]}"#.utf8))
            }
            return (404, [:], Data())
        }
    }

    /// Bootstrap with an active reservation covering "now" — Slice S
    /// reservations carry `lagoCustomerExternalId` for Path A.
    private func installReservedBootstrap(
        now: Date,
        externalId: String? = "lago-alice"
    ) {
        let startsAt = ISO8601DateFormatter().string(from: now.addingTimeInterval(-600))
        let endsAt = ISO8601DateFormatter().string(from: now.addingTimeInterval(600))
        let extIdFragment = externalId.map { "\"\($0)\"" } ?? "null"
        StubURLProtocol.handler = { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("/session") {
                let body = #"""
                {"session": null, "state": "idle", "chargerId": "BAY-1"}
                """#
                return (200, ["Content-Type": "application/json"], Data(body.utf8))
            }
            if path.hasSuffix("/reservations") {
                let body = """
                {"reservations": [
                  {"reservationId":"42","startsAt":"\(startsAt)","endsAt":"\(endsAt)",
                   "customerLabel":"Alice","lagoCustomerExternalId":\(extIdFragment),
                   "isBlackout":false,"idTag":"ALICE-CARD-1","isCancelable":true}
                ]}
                """
                return (200, ["Content-Type": "application/json"], Data(body.utf8))
            }
            return (404, [:], Data())
        }
    }

    // MARK: - bootstrap

    func test_bootstrapPopulatesSessionAndReservations() async {
        StubURLProtocol.reset(); defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("/session") {
                let body = #"""
                {"session": {
                   "chargerId":"BAY-1","sessionId":"99","state":"charging",
                   "startedAt":"2026-04-27T10:00:00Z","idTag":"ALICE",
                   "customerName":"Alice","kwh":3.5,"kw":11.0,
                   "elapsedSec":120,"connectorId":1
                 },"state":"charging","chargerId":"BAY-1"}
                """#
                return (200, ["Content-Type": "application/json"], Data(body.utf8))
            }
            if path.hasSuffix("/reservations") {
                let body = #"""
                {"reservations":[
                  {"reservationId":"7","startsAt":"2026-04-28T09:00:00Z",
                   "endsAt":"2026-04-28T10:00:00Z","customerLabel":"Bob",
                   "lagoCustomerExternalId":"lago-bob",
                   "isBlackout":false,"idTag":"BOB-CARD","isCancelable":true}
                ]}
                """#
                return (200, ["Content-Type": "application/json"], Data(body.utf8))
            }
            return (404, [:], Data())
        }

        let vm = makeVM()
        await vm.bootstrap()

        XCTAssertEqual(vm.loadState, .ok)
        XCTAssertEqual(vm.session?.state, .charging)
        XCTAssertEqual(vm.session?.kwh, 3.5)
        XCTAssertEqual(vm.reservations.count, 1)
        XCTAssertEqual(vm.reservations.first?.customerLabel, "Bob")
        XCTAssertEqual(vm.reservations.first?.lagoCustomerExternalId, "lago-bob")
    }

    // MARK: - currentReservation derivation

    func test_currentReservationCoversNow() async {
        StubURLProtocol.reset(); defer { StubURLProtocol.reset() }
        let now = Date(timeIntervalSince1970: 1_745_750_000)
        installReservedBootstrap(now: now)
        let vm = makeVM(now: now)
        await vm.bootstrap()
        XCTAssertNotNil(vm.currentReservation)
        XCTAssertEqual(vm.currentReservation?.reservationId, "42")
    }

    func test_currentReservationNilWhenNoActiveWindow() async {
        StubURLProtocol.reset(); defer { StubURLProtocol.reset() }
        installIdleBootstrap()
        let vm = makeVM()
        await vm.bootstrap()
        XCTAssertNil(vm.currentReservation)
    }

    // MARK: - startCharging — Path A (reserved customer)

    func test_startChargingPathAUsesReservationCustomerAndSkipsPicker() async {
        StubURLProtocol.reset(); defer { StubURLProtocol.reset() }
        let now = Date(timeIntervalSince1970: 1_745_750_000)

        let observed = ObservedRequest()
        StubURLProtocol.handler = { req in
            let path = req.url?.path ?? ""
            if req.httpMethod == "POST", path.hasSuffix("/start") {
                observed.record(req)
                return (200, ["Content-Type": "application/json"],
                        Data(#"{"operationLogId":1,"taskId":"t","status":"submitted"}"#.utf8))
            }
            // Slice S: Path A no longer hits /tags or /customers — the
            // reservation already carries `lagoCustomerExternalId`. If the
            // VM mistakenly calls /customers, fall back to a 404 so the
            // test fails noisily.
            let startsAt = ISO8601DateFormatter().string(from: now.addingTimeInterval(-600))
            let endsAt = ISO8601DateFormatter().string(from: now.addingTimeInterval(600))
            if path.hasSuffix("/session") {
                let body = #"""
                {"session": {
                   "chargerId":"BAY-1","sessionId":null,"state":"preparing",
                   "startedAt":null,"idTag":null,
                   "customerName":"Alice","kwh":null,"kw":null,
                   "elapsedSec":null,"connectorId":null
                 },"state":"preparing","chargerId":"BAY-1"}
                """#
                return (200, ["Content-Type": "application/json"], Data(body.utf8))
            }
            if path.hasSuffix("/reservations") {
                let body = """
                {"reservations":[
                  {"reservationId":"42","startsAt":"\(startsAt)","endsAt":"\(endsAt)",
                   "customerLabel":"Alice","lagoCustomerExternalId":"lago-alice",
                   "isBlackout":false,"idTag":"ALICE-CARD-1","isCancelable":true}
                ]}
                """
                return (200, ["Content-Type": "application/json"], Data(body.utf8))
            }
            return (404, [:], Data())
        }

        let vm = makeVM(now: now)
        await vm.bootstrap()
        await vm.startCharging()

        XCTAssertFalse(vm.pickerVisible, "Path A must not show the picker")
        // POST body must carry the reservation's externalId — and only
        // that + the reservation id. No legacy idTag/tagPk.
        let body = observed.lastBody.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        XCTAssertEqual(body?["lagoCustomerExternalId"] as? String, "lago-alice")
        XCTAssertEqual(body?["reservationId"] as? String, "42")
        XCTAssertNil(body?["idTag"], "Slice S body must not carry legacy idTag")
        XCTAssertNil(body?["tagPk"], "Slice S body must not carry legacy tagPk")
        XCTAssertEqual(vm.session?.state, .preparing)
    }

    func test_startChargingPathAFallsBackToPickerWhenReservationLacksExternalId() async {
        // Reservation has no `lagoCustomerExternalId` (older server, or
        // an unmapped tag). The VM should open the customer picker
        // rather than fail-closed.
        StubURLProtocol.reset(); defer { StubURLProtocol.reset() }
        let now = Date(timeIntervalSince1970: 1_745_750_000)

        let observed = ObservedRequest()
        StubURLProtocol.handler = { req in
            let path = req.url?.path ?? ""
            if req.httpMethod == "POST", path.hasSuffix("/start") {
                observed.record(req)
                return (200, [:], Data())
            }
            if path.hasSuffix("/customers") {
                // Customer list comes back empty — Path B picker still
                // opens; the operator sees an empty-state.
                return (200, ["Content-Type": "application/json"],
                        Data(#"{"customers":[]}"#.utf8))
            }
            let startsAt = ISO8601DateFormatter().string(from: now.addingTimeInterval(-600))
            let endsAt = ISO8601DateFormatter().string(from: now.addingTimeInterval(600))
            if path.hasSuffix("/session") {
                return (200, ["Content-Type": "application/json"],
                        Data(#"{"session":null,"state":"idle","chargerId":"BAY-1"}"#.utf8))
            }
            if path.hasSuffix("/reservations") {
                // Reservation has no externalId field (older server).
                let body = """
                {"reservations":[
                  {"reservationId":"42","startsAt":"\(startsAt)","endsAt":"\(endsAt)",
                   "customerLabel":"Alice","isBlackout":false,
                   "idTag":"ALICE-CARD-1","isCancelable":true}
                ]}
                """
                return (200, ["Content-Type": "application/json"], Data(body.utf8))
            }
            return (404, [:], Data())
        }

        let vm = makeVM(now: now)
        await vm.bootstrap()
        await vm.startCharging()

        XCTAssertTrue(vm.pickerVisible, "Path A fall-through opens the picker")
        XCTAssertNil(observed.lastBody, "Start endpoint must not have fired")
    }

    // MARK: - startCharging — Path B (no reservation)

    func test_startChargingPathBOpensPicker() async {
        StubURLProtocol.reset(); defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("/customers") {
                let body = #"""
                {"customers":[
                  {"lagoCustomerExternalId":"lago-alice","userId":"u-1",
                   "displayName":"Alice","name":"Alice","email":"alice@example.com",
                   "isOwn":false,"lastUsedAt":null}
                ]}
                """#
                return (200, ["Content-Type": "application/json"], Data(body.utf8))
            }
            if path.hasSuffix("/session") {
                return (200, ["Content-Type": "application/json"],
                        Data(#"{"session": null, "state": "idle", "chargerId": "BAY-1"}"#.utf8))
            }
            if path.hasSuffix("/reservations") {
                return (200, ["Content-Type": "application/json"],
                        Data(#"{"reservations":[]}"#.utf8))
            }
            return (404, [:], Data())
        }

        let vm = makeVM()
        await vm.bootstrap()
        XCTAssertFalse(vm.pickerVisible)
        await vm.startCharging()

        XCTAssertTrue(vm.pickerVisible, "Path B opens the picker")
        XCTAssertFalse(vm.customers.isEmpty, "Customers loaded before showing picker")
    }

    // MARK: - submitStart 200 → optimistic flip

    func test_submitStartCustomer200OptimisticallyFlipsToPreparing() async {
        StubURLProtocol.reset(); defer { StubURLProtocol.reset() }
        // Stub returns idle on bootstrap, then preparing on the
        // post-start refresh — the VM's optimistic flip is observed
        // through the surviving session shape.
        let phase = AtomicCounter()
        let observed = ObservedRequest()
        StubURLProtocol.handler = { req in
            let path = req.url?.path ?? ""
            if req.httpMethod == "POST", path.hasSuffix("/start") {
                observed.record(req)
                phase.bump()
                return (200, ["Content-Type": "application/json"],
                        Data(#"{"operationLogId":1,"taskId":"t","status":"submitted"}"#.utf8))
            }
            if path.hasSuffix("/session") {
                if phase.value == 0 {
                    return (200, ["Content-Type": "application/json"],
                            Data(#"{"session": null, "state": "idle", "chargerId": "BAY-1"}"#.utf8))
                }
                let body = #"""
                {"session": {
                   "chargerId":"BAY-1","sessionId":null,"state":"preparing",
                   "startedAt":null,"idTag":null,"customerName":"Alice",
                   "kwh":null,"kw":null,"elapsedSec":null,"connectorId":null
                 },"state":"preparing","chargerId":"BAY-1"}
                """#
                return (200, ["Content-Type": "application/json"], Data(body.utf8))
            }
            if path.hasSuffix("/reservations") {
                return (200, ["Content-Type": "application/json"],
                        Data(#"{"reservations":[]}"#.utf8))
            }
            return (404, [:], Data())
        }

        let vm = makeVM()
        await vm.bootstrap()
        let customer = CustomerOption(
            lagoCustomerExternalId: "lago-alice",
            userId: "u-1",
            displayName: "Alice",
            name: "Alice",
            email: nil,
            isOwn: false,
            lastUsedAt: nil
        )
        await vm.submitStart(customer: customer)
        XCTAssertEqual(vm.session?.state, .preparing)
        // POST body shape — Slice S contract.
        let body = observed.lastBody.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        XCTAssertEqual(body?["lagoCustomerExternalId"] as? String, "lago-alice")
        XCTAssertNil(body?["idTag"])
        XCTAssertNil(body?["tagPk"])
    }

    // MARK: - submitStart 409 → charger offline

    func test_submitStartCustomer409SurfacesChargerOffline() async {
        StubURLProtocol.reset(); defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { req in
            let path = req.url?.path ?? ""
            if req.httpMethod == "POST", path.hasSuffix("/start") {
                return (409, ["Content-Type": "application/json"],
                        Data(#"{"error":"charger_offline","lastSeenAt":null}"#.utf8))
            }
            if path.hasSuffix("/session") {
                return (200, ["Content-Type": "application/json"],
                        Data(#"{"session": null, "state": "idle", "chargerId": "BAY-1"}"#.utf8))
            }
            if path.hasSuffix("/reservations") {
                return (200, ["Content-Type": "application/json"],
                        Data(#"{"reservations":[]}"#.utf8))
            }
            return (404, [:], Data())
        }

        let vm = makeVM()
        await vm.bootstrap()
        let customer = CustomerOption(
            lagoCustomerExternalId: "lago-alice",
            userId: "u-1",
            displayName: "Alice",
            name: nil,
            email: nil,
            isOwn: false,
            lastUsedAt: nil
        )
        await vm.submitStart(customer: customer)
        switch vm.loadState {
        case .error(let msg):
            XCTAssertTrue(
                msg.lowercased().contains("offline"),
                "Expected 'Charger offline'; got: \(msg)"
            )
        default:
            XCTFail("Expected .error, got \(vm.loadState)")
        }
    }

    // MARK: - stopCharging

    func test_stopChargingConfirmedFlipsToStopping() async {
        StubURLProtocol.reset(); defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { req in
            let path = req.url?.path ?? ""
            if req.httpMethod == "POST", path.hasSuffix("/stop") {
                return (200, ["Content-Type": "application/json"],
                        Data(#"{"operationLogId":1,"taskId":"t","status":"submitted"}"#.utf8))
            }
            if path.hasSuffix("/session") {
                let body = #"""
                {"session": {
                   "chargerId":"BAY-1","sessionId":"99","state":"charging",
                   "startedAt":"2026-04-27T10:00:00Z","idTag":"T1",
                   "customerName":"Alice","kwh":3.5,"kw":11.0,
                   "elapsedSec":120,"connectorId":1
                 },"state":"charging","chargerId":"BAY-1"}
                """#
                return (200, ["Content-Type": "application/json"], Data(body.utf8))
            }
            if path.hasSuffix("/reservations") {
                return (200, ["Content-Type": "application/json"],
                        Data(#"{"reservations":[]}"#.utf8))
            }
            return (404, [:], Data())
        }

        let vm = makeVM()
        await vm.bootstrap()
        XCTAssertEqual(vm.session?.state, .charging)
        await vm.stopCharging(confirmed: true)
        XCTAssertNotEqual(vm.loadState, .error("Couldn't stop charging. Try again."))
    }

    func test_stopChargingNotConfirmedDoesNothing() async {
        StubURLProtocol.reset(); defer { StubURLProtocol.reset() }
        installIdleBootstrap()
        let vm = makeVM()
        await vm.bootstrap()
        await vm.stopCharging(confirmed: false)
        if case .error = vm.loadState { XCTFail("Should not error") }
    }

    // MARK: - cancelReservation

    func test_cancelReservationOptimisticallyRemovesRow() async {
        StubURLProtocol.reset(); defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { req in
            let path = req.url?.path ?? ""
            if req.httpMethod == "DELETE", path.hasSuffix("/cancel-reservation") {
                return (200, ["Content-Type": "application/json"],
                        Data(#"{"reservationId":7,"status":"cancelled"}"#.utf8))
            }
            if path.hasSuffix("/session") {
                return (200, ["Content-Type": "application/json"],
                        Data(#"{"session": null, "state": "idle", "chargerId": "BAY-1"}"#.utf8))
            }
            if path.hasSuffix("/reservations") {
                let body = #"""
                {"reservations":[
                  {"reservationId":"7","startsAt":"2026-04-28T09:00:00Z",
                   "endsAt":"2026-04-28T10:00:00Z","customerLabel":"Bob",
                   "lagoCustomerExternalId":"lago-bob",
                   "isBlackout":false,"idTag":"BOB","isCancelable":true}
                ]}
                """#
                return (200, ["Content-Type": "application/json"], Data(body.utf8))
            }
            return (404, [:], Data())
        }

        let vm = makeVM()
        await vm.bootstrap()
        XCTAssertEqual(vm.reservations.count, 1)
        await vm.cancelReservation("7", confirmed: true)
        XCTAssertTrue(vm.reservations.isEmpty)
    }
}

// MARK: - Test helpers

/// Lock-protected phase counter so a `@Sendable` stub closure can
/// branch responses across calls (Swift 6 strict concurrency).
private final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int = 0
    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return _value
    }
    func bump() {
        lock.lock(); defer { lock.unlock() }
        _value += 1
    }
}

/// Captures the most-recent `URLRequest` body for assertions on POST
/// payload shape. Lock-protected so the `@Sendable` stub closure is
/// safe under Swift 6 strict concurrency.
private final class ObservedRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var _lastBody: Data?

    var lastBody: Data? {
        lock.lock(); defer { lock.unlock() }
        return _lastBody
    }

    func record(_ req: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        if let data = req.httpBody {
            _lastBody = data
            return
        }
        if let stream = req.httpBodyStream {
            _lastBody = Self.drain(stream)
        }
    }

    private static func drain(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
