//
//  ContractRoundTripTests.swift
//  ModelsTests
//
//  Decode JSON samples drawn from `docs/plan/20-contracts.md`, encode back,
//  and assert structural equivalence. Confirms our Codable wrappers match
//  the canonical TS contracts at the wire level.
//

import Foundation
import Testing
@testable import Models

@Suite("Contract round-trip")
struct ContractRoundTripTests {

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .useDefaultKeys
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    // MARK: - EnrichedScanResult

    @Test func enrichedScanResultRoundTrip() throws {
        let json = """
        {
          "ok": true,
          "found": true,
          "pairingCode": "X7R2KQ",
          "idTag": "04AB12CDEF1234",
          "resolvedAtIso": "2026-04-25T12:34:56.000Z",
          "tag": {
            "displayName": "Aisha's Card",
            "tagType": "ev_card"
          },
          "customer": {
            "displayName": "Aisha Patel",
            "slug": "aisha-patel"
          },
          "subscription": {
            "planLabel": "Standard EV",
            "status": "active",
            "currentPeriodEndIso": "2026-05-25T00:00:00.000Z",
            "billingTier": "standard"
          }
        }
        """

        let decoded = try decoder.decode(
            EnrichedScanResult.self,
            from: Data(json.utf8)
        )

        #expect(decoded.ok == true)
        #expect(decoded.found == true)
        #expect(decoded.pairingCode == "X7R2KQ")
        #expect(decoded.idTag == "04AB12CDEF1234")
        #expect(decoded.tag?.tagType == "ev_card")
        #expect(decoded.customer?.slug == "aisha-patel")
        #expect(decoded.subscription?.status == .active)
        #expect(decoded.subscription?.billingTier == .standard)

        let reEncoded = try encoder.encode(decoded)
        let reDecoded = try decoder.decode(EnrichedScanResult.self, from: reEncoded)
        #expect(decoded == reDecoded)
    }

    @Test func enrichedScanResultHandlesNulls() throws {
        let json = """
        {
          "ok": true,
          "found": false,
          "pairingCode": "X7R2KQ",
          "idTag": "04AB12CDEF1234",
          "resolvedAtIso": "2026-04-25T12:34:56.000Z",
          "tag": null,
          "customer": null,
          "subscription": null
        }
        """
        let decoded = try decoder.decode(
            EnrichedScanResult.self,
            from: Data(json.utf8)
        )
        #expect(decoded.found == false)
        #expect(decoded.tag == nil)
        #expect(decoded.customer == nil)
        #expect(decoded.subscription == nil)
    }

    // MARK: - DeviceScanRequestedPayload (a.k.a. ScanRequest)

    @Test func scanRequestRoundTrip() throws {
        let json = """
        {
          "deviceId": "11111111-2222-3333-4444-555555555555",
          "pairingCode": "X7R2KQ",
          "purpose": "admin-link",
          "expiresAtIso": "2026-04-25T12:35:30.000Z",
          "expiresAtEpochMs": 1745622090000,
          "requestedByUserId": "alice",
          "hintLabel": "Front desk"
        }
        """
        let decoded = try decoder.decode(ScanRequest.self, from: Data(json.utf8))
        #expect(decoded.deviceId == "11111111-2222-3333-4444-555555555555")
        #expect(decoded.purpose == .adminLink)
        #expect(decoded.expiresAtEpochMs == 1745622090000)
        #expect(decoded.hintLabel == "Front desk")

        let reEncoded = try encoder.encode(decoded)
        let reDecoded = try decoder.decode(ScanRequest.self, from: reEncoded)
        #expect(decoded == reDecoded)
    }

    @Test func scanRequestSystemInitiated() throws {
        let json = """
        {
          "deviceId": "uuid",
          "pairingCode": "X7R2KQ",
          "purpose": "login",
          "expiresAtIso": "2026-04-25T12:35:30.000Z",
          "expiresAtEpochMs": 1745622090000,
          "requestedByUserId": null,
          "hintLabel": null
        }
        """
        let decoded = try decoder.decode(ScanRequest.self, from: Data(json.utf8))
        #expect(decoded.purpose == .login)
        #expect(decoded.requestedByUserId == nil)
        #expect(decoded.hintLabel == nil)
    }

    // MARK: - DeviceRegistrationResponse

    @Test func deviceRegistrationResponseRoundTrip() throws {
        let json = """
        {
          "ok": true,
          "deviceId": "11111111-2222-3333-4444-555555555555",
          "deviceToken": "dev_abc123def456",
          "deviceSecret": "QkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkI",
          "capabilities": ["scanner"],
          "expiresAtIso": "2027-04-25T12:34:56.000Z"
        }
        """
        let decoded = try decoder.decode(
            DeviceRegistrationResponse.self,
            from: Data(json.utf8)
        )
        #expect(decoded.deviceToken.hasPrefix("dev_"))
        #expect(decoded.capabilities == [.scanner])

        let reEncoded = try encoder.encode(decoded)
        let reDecoded = try decoder.decode(
            DeviceRegistrationResponse.self,
            from: reEncoded
        )
        #expect(decoded == reDecoded)
    }

    // MARK: - DeviceRegistrationRequest (sanity)

    @Test func deviceRegistrationRequestRoundTrip() throws {
        let request = DeviceRegistrationRequest(
            oneTimeCode: "abc123",
            codeVerifier: "def456",
            label: "Aisha's iPhone",
            platform: "ios",
            model: "iPhone 16 Pro",
            osVersion: "18.4.1",
            appVersion: "1.0.0",
            pushToken: "Zm9v",
            apnsEnvironment: .sandbox,
            requestedCapabilities: [.scanner]
        )
        let data = try encoder.encode(request)
        let decoded = try decoder.decode(
            DeviceRegistrationRequest.self,
            from: data
        )
        #expect(decoded == request)

        // Verify wire format uses camelCase.
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["oneTimeCode"] != nil)
        #expect(object?["codeVerifier"] != nil)
        #expect(object?["apnsEnvironment"] != nil)
        #expect(object?["requestedCapabilities"] != nil)
        #expect(object?["one_time_code"] == nil)
        #expect(object?["code_verifier"] == nil)
    }

    // MARK: - HeartbeatPayload + ScanResultRequest

    @Test func heartbeatPayloadOptionalFields() throws {
        let empty = HeartbeatPayload()
        let data = try encoder.encode(empty)
        let decoded = try decoder.decode(HeartbeatPayload.self, from: data)
        #expect(decoded == empty)

        let populated = HeartbeatPayload(appVersion: "1.0.0", osVersion: "18.4.1")
        let data2 = try encoder.encode(populated)
        let decoded2 = try decoder.decode(HeartbeatPayload.self, from: data2)
        #expect(decoded2 == populated)
    }

    @Test func scanResultRequestRoundTrip() throws {
        let req = ScanResultRequest(
            idTag: "04AB12CDEF1234",
            pairingCode: "X7R2KQ",
            ts: 1745622000,
            nonce: "2345bb48"
        )
        let data = try encoder.encode(req)
        let decoded = try decoder.decode(ScanResultRequest.self, from: data)
        #expect(decoded == req)

        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["idTag"] as? String == "04AB12CDEF1234")
    }
}
