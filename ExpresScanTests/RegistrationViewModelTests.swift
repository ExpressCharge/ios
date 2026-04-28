//
//  RegistrationViewModelTests.swift
//  ExpresScanTests
//
//  Tests for the Wave 6 / Slice H additions to `RegistrationViewModel`:
//  capability picker defaults, legality validation, label fallback, and
//  the wire shape of the registration POST body.
//
//  Spec: `50-ios.md` § "Registration capability picker" + the H plan.
//

import XCTest
@testable import ExpresScan
import AuthCore
import Capabilities
import Models
import Networking

@MainActor
final class RegistrationViewModelTests: XCTestCase {

    // MARK: - Picker contract

    func test_capabilityPickerOffersAppEligibleSet() {
        // Apps cannot self-register as chargers, so the picker must
        // expose exactly {.scanner, .user, .kiosk}.
        let keys = Set(CapabilityMetadata.registrationOptions.map(\.key))
        XCTAssertEqual(keys, Set([.scanner, .user, .kiosk]))
        XCTAssertFalse(keys.contains(.charger))
    }

    func test_defaultSelectionIsScannerAndUser() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.selectedCapabilities, Set([.scanner, .user]))
    }

    // MARK: - Submit body

    func test_submitSendsSelectedCapabilities() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }

        let captured = CapturedRequest()
        StubURLProtocol.handler = { request in
            captured.body = request.httpBodyOrStreamData()
            let response = #"""
            {"ok":true,"deviceId":"dev_1","deviceToken":"t","deviceSecret":"s","capabilities":["scanner","user"],"expiresAtIso":"2099-01-01T00:00:00Z"}
            """#
            return (200, ["Content-Type": "application/json"], Data(response.utf8))
        }

        let vm = makeViewModel()
        vm.selectedCapabilities = [.kiosk, .scanner] // legal: kiosk + 1 base
        await vm.submit()

        let body = try XCTUnwrap(captured.body)
        let decoded = try JSONDecoder().decode(DeviceRegistrationRequest.self, from: body)
        // The submit() method sorts capabilities by raw value for
        // deterministic test fixtures.
        XCTAssertEqual(decoded.requestedCapabilities, [.kiosk, .scanner].sorted { $0.rawValue < $1.rawValue })
    }

    func test_submitRejectsIllegalCapabilitySet() async {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        // Stub set up to FAIL the test if the network is hit — illegal
        // sets must short-circuit before any wire activity.
        let hitNetwork = NetworkHitFlag()
        StubURLProtocol.handler = { _ in
            hitNetwork.didHit = true
            return (500, [:], Data())
        }

        let vm = makeViewModel()
        vm.selectedCapabilities = [.scanner, .user, .kiosk] // illegal
        await vm.submit()

        XCTAssertEqual(vm.error, .invalidCapabilities)
        XCTAssertFalse(hitNetwork.didHit, "Illegal capability set must not reach the network")
    }

    func test_submitRejectsEmptyCapabilitySet() async {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }

        let vm = makeViewModel()
        vm.selectedCapabilities = []
        await vm.submit()

        XCTAssertEqual(vm.error, .invalidCapabilities)
    }

    // MARK: - Label fallback

    func test_labelFallback_whenDeviceNameIsGeneric_iPhone() {
        // When the user-assigned-device-name entitlement isn't granted,
        // iOS returns the generic "iPhone" — substitute model + last-4
        // of the device id.
        let resolved = RegistrationViewModel.resolveDefaultLabel(
            deviceName: "iPhone",
            localizedModel: "iPhone",
            deviceIdLast4: "ABCD"
        )
        XCTAssertEqual(resolved, "iPhone (ABCD)")
    }

    func test_labelFallback_whenDeviceNameIsGeneric_iPad() {
        let resolved = RegistrationViewModel.resolveDefaultLabel(
            deviceName: "iPad",
            localizedModel: "iPad",
            deviceIdLast4: "1234"
        )
        XCTAssertEqual(resolved, "iPad (1234)")
    }

    func test_labelFallback_passesThroughUserAssignedName() {
        let resolved = RegistrationViewModel.resolveDefaultLabel(
            deviceName: "Vlad's iPhone",
            localizedModel: "iPhone",
            deviceIdLast4: "ABCD"
        )
        XCTAssertEqual(resolved, "Vlad's iPhone")
    }

    func test_initUsesLabelFallback_forGenericDeviceName() {
        let vm = makeViewModel(
            deviceName: "iPhone",
            localizedModel: "iPhone",
            deviceId: "00000000-0000-0000-0000-0000DEADBEEF"
        )
        XCTAssertEqual(vm.label, "iPhone (BEEF)")
    }

    // MARK: - Helpers

    private func makeViewModel(
        deviceName: String = "Vlad's iPhone",
        localizedModel: String = "iPhone",
        deviceId: String = "00000000-0000-0000-0000-000000000000"
    ) -> RegistrationViewModel {
        RegistrationViewModel(
            environment: makeStubEnvironment(),
            oneTimeCode: "ot_test",
            codeVerifier: "v_test",
            deviceName: deviceName,
            localizedModel: localizedModel,
            deviceIdProvider: { deviceId }
        )
    }

    private func makeStubEnvironment() -> AppEnvironment {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let api = APIClient(
            baseURL: URL(string: "https://example.test")!,
            transport: session,
            tokenSource: { nil }
        )
        // AuthStore on simulator writes to the test bundle's keychain;
        // that's fine for the body-capture test where the fake response
        // includes the three secrets and storeCredentials succeeds.
        return AppEnvironment(api: api, authStore: AuthStore())
    }
}

// MARK: - Test plumbing

/// Mutable container so the URL-protocol handler closure can ferry the
/// captured body back to the test method without a mutable capture.
private final class CapturedRequest: @unchecked Sendable {
    var body: Data?
}

private final class NetworkHitFlag: @unchecked Sendable {
    var didHit: Bool = false
}

private extension URLRequest {
    /// `URLRequest.httpBody` is nil when the body was set via
    /// `httpBodyStream` — `URLSession`'s `URLProtocol` path uses the
    /// stream form. Drain whichever is populated.
    func httpBodyOrStreamData() -> Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
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
