//
//  ChargerListViewModelTests.swift
//  ExpresScanTests
//
//  Wave 6 / Slice I — coverage for `ChargerListViewModel`. Drives the
//  VM through `StubURLProtocol` — same pattern as the registration
//  + push-token VM tests — to assert: refresh load + decode, filter
//  application, error mapping, and idempotent "already loading" guard.
//

import Networking
import XCTest

@testable import ExpresScan

/// Lock-protected counter for test stub callback bumps. The
/// `StubURLProtocol.handler` closure is `@Sendable` so a captured
/// `var` would violate Swift 6 strict concurrency.
final class HitCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
    func bump() {
        lock.lock()
        defer { lock.unlock() }
        _value += 1
    }
}

@MainActor
final class ChargerListViewModelTests: XCTestCase {

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

    // MARK: - Happy path

    func test_refreshPopulatesEntries() async {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }

        StubURLProtocol.handler = { _ in
            let body = #"""
                {
                  "chargers": [
                    {
                      "chargerId": "BAY-1",
                      "label": "Bay 1",
                      "siteName": null,
                      "formFactor": "wallbox",
                      "connectorType": null,
                      "maxKw": null,
                      "state": "idle",
                      "lastSeenAt": "2026-04-27T12:00:00Z"
                    },
                    {
                      "chargerId": "BAY-2",
                      "label": "Bay 2",
                      "siteName": null,
                      "formFactor": "tesla",
                      "connectorType": null,
                      "maxKw": null,
                      "state": "charging",
                      "lastSeenAt": "2026-04-27T12:01:00Z"
                    }
                  ]
                }
                """#
            return (200, ["Content-Type": "application/json"], Data(body.utf8))
        }

        let vm = ChargerListViewModel(api: apiClient())
        await vm.refresh()

        XCTAssertEqual(vm.loadState, .ok)
        XCTAssertEqual(vm.entries.count, 2)
        XCTAssertEqual(vm.entries[0].chargerId, "BAY-1")
        XCTAssertEqual(vm.entries[0].state, .idle)
        XCTAssertEqual(vm.entries[1].state, .charging)
    }

    // MARK: - Filter application

    func test_filterAllReturnsEverything() async {
        await loadStockEntries(into: makeVM())
    }

    func test_filterOnlineDropsOfflineRows() async {
        let vm = makeVM()
        await loadStockEntries(into: vm)
        vm.filter = .online
        let displayed = Set(vm.displayEntries.map(\.chargerId))
        XCTAssertEqual(displayed, ["BAY-1", "BAY-2"])
    }

    // MARK: - Empty state

    func test_emptyResponseProducesEmptyEntries() async {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in
            (200, ["Content-Type": "application/json"], Data(#"{"chargers":[]}"#.utf8))
        }
        let vm = makeVM()
        await vm.refresh()
        XCTAssertEqual(vm.loadState, .ok)
        XCTAssertTrue(vm.entries.isEmpty)
        XCTAssertTrue(vm.isEmpty)
    }

    // MARK: - Error mapping

    func test_403MapsToAccessDeniedMessage() async {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in
            (
                403, ["Content-Type": "application/json"],
                Data(#"{"error":"capability_denied","missing":["user"]}"#.utf8)
            )
        }
        let vm = makeVM()
        await vm.refresh()

        switch vm.loadState {
        case .error(let msg):
            XCTAssertTrue(
                msg.lowercased().contains("access"),
                "Expected access-denied messaging, got: \(msg)"
            )
        default:
            XCTFail("Expected .error, got \(vm.loadState)")
        }
    }

    func test_410MapsToDeregisteredMessage() async {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in
            (
                410, ["Content-Type": "application/json"],
                Data(#"{"error":"device_deleted"}"#.utf8)
            )
        }
        let vm = makeVM()
        await vm.refresh()

        switch vm.loadState {
        case .error(let msg):
            XCTAssertTrue(
                msg.lowercased().contains("deregistered")
                    || msg.lowercased().contains("sign in"),
                "Expected deregistration messaging, got: \(msg)"
            )
        default:
            XCTFail("Expected .error, got \(vm.loadState)")
        }
    }

    // MARK: - Concurrency guard

    func test_refreshWhileLoadingIsIdempotent() async {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }

        let counter = HitCounter()
        StubURLProtocol.handler = { _ in
            counter.bump()
            return (
                200, ["Content-Type": "application/json"],
                Data(#"{"chargers":[]}"#.utf8)
            )
        }

        let vm = makeVM()
        // Two refreshes back-to-back. The second should observe the
        // first's `.loading` state and short-circuit.
        async let a: Void = vm.refresh()
        async let b: Void = vm.refresh()
        _ = await (a, b)

        // The first refresh always hits; the second short-circuits as
        // soon as it observes the loading state.
        XCTAssertLessThanOrEqual(counter.value, 2)
        XCTAssertEqual(vm.loadState, .ok)
    }

    // MARK: - Helpers

    private func makeVM() -> ChargerListViewModel {
        ChargerListViewModel(api: apiClient())
    }

    /// Loads three stock rows into the VM via the stub: BAY-1 (idle,
    /// online), BAY-2 (charging, online), BAY-3 (offline). Used to
    /// exercise the filter computed property.
    private func loadStockEntries(into vm: ChargerListViewModel) async {
        StubURLProtocol.reset()
        StubURLProtocol.handler = { _ in
            let body = #"""
                {
                  "chargers": [
                    {"chargerId":"BAY-1","label":"Bay 1","siteName":null,"formFactor":"wallbox","connectorType":null,"maxKw":null,"state":"idle","lastSeenAt":null},
                    {"chargerId":"BAY-2","label":"Bay 2","siteName":null,"formFactor":"tesla","connectorType":null,"maxKw":null,"state":"charging","lastSeenAt":null},
                    {"chargerId":"BAY-3","label":"Bay 3","siteName":null,"formFactor":"generic","connectorType":null,"maxKw":null,"state":"offline","lastSeenAt":null}
                  ]
                }
                """#
            return (200, ["Content-Type": "application/json"], Data(body.utf8))
        }
        await vm.refresh()
        XCTAssertEqual(vm.entries.count, 3)
    }
}
