//
//  DeviceStatePayloadTests.swift
//  DeviceSyncTests
//
//  Round-trip the `DeviceState` envelope JSON against canonical fixtures
//  matching the plan's `DeviceState` shape.
//

import Foundation
import Testing

@testable import DeviceSync
@testable import Models

@Suite("DeviceState — wire round-trip")
struct DeviceStatePayloadTests {

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .useDefaultKeys
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    @Test func decodesFullEnvelope() throws {
        let json = """
            {
              "device": {
                "id": "dev_123",
                "label": "Vlad's iPhone",
                "kind": "phone_nfc",
                "ownerUserId": "usr_abc",
                "siteId": null,
                "registeredAt": "2026-04-01T12:00:00.000Z",
                "lastSeenAt": "2026-04-27T09:30:00.000Z"
              },
              "capabilities": ["scanner", "user"],
              "kioskAllowed": false,
              "ownerUser": { "id": "usr_abc", "role": "admin", "displayName": "Vlad" },
              "settings": {
                "device.label": {
                  "value": "Vlad's iPhone",
                  "updatedAt": "2026-04-27T09:00:00Z",
                  "updatedBy": "ios-app"
                },
                "notifications.scanRequest": {
                  "value": true,
                  "updatedAt": "2026-04-26T20:00:00Z",
                  "updatedBy": "admin"
                }
              },
              "scanStatus": {
                "armed": true,
                "pairingCode": "X7R2KQ",
                "expiresAt": "2026-04-27T09:35:00Z"
              },
              "pushToken": { "last8": "abcd1234", "environment": "production" },
              "connectivity": {
                "online": true,
                "lastSyncAt": "2026-04-27T09:30:00Z",
                "reconnectCount": 2,
                "pendingUploads": 0
              }
            }
            """

        let data = Data(json.utf8)
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .useDefaultKeys
        // settings values include ISO date strings — decode dates.
        dec.dateDecodingStrategy = .iso8601

        let state = try dec.decode(DeviceState.self, from: data)

        #expect(state.device.id == "dev_123")
        #expect(state.device.kind == .phoneNFC)
        #expect(state.device.siteId == nil)
        #expect(state.capabilities == [.scanner, .user])
        #expect(state.kioskAllowed == false)
        #expect(state.ownerUser.role == .admin)
        #expect(state.ownerUser.displayName == "Vlad")
        #expect(state.settings.count == 2)
        #expect(state.settings["device.label"]?.value == .string("Vlad's iPhone"))
        #expect(state.settings["notifications.scanRequest"]?.value == .bool(true))
        #expect(state.scanStatus?.armed == true)
        #expect(state.scanStatus?.pairingCode == "X7R2KQ")
        #expect(state.pushToken?.last8 == "abcd1234")
        #expect(state.pushToken?.environment == .production)
        #expect(state.connectivity.online == true)
        #expect(state.connectivity.reconnectCount == 2)
    }

    @Test func decodesNullScanStatusAndPushToken() throws {
        let json = """
            {
              "device": {
                "id": "dev_42",
                "label": "Kiosk-only iPad",
                "kind": "laptop_nfc",
                "ownerUserId": "usr_x",
                "siteId": "site_1",
                "registeredAt": "2026-04-01T12:00:00.000Z",
                "lastSeenAt": "2026-04-27T09:30:00.000Z"
              },
              "capabilities": ["user", "kiosk"],
              "kioskAllowed": true,
              "ownerUser": { "id": "usr_x", "role": "customer", "displayName": "Cust" },
              "settings": {},
              "scanStatus": null,
              "pushToken": null,
              "connectivity": {
                "online": false,
                "lastSyncAt": null,
                "reconnectCount": 0,
                "pendingUploads": 3
              }
            }
            """
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let state = try dec.decode(DeviceState.self, from: Data(json.utf8))
        #expect(state.scanStatus == nil)
        #expect(state.pushToken == nil)
        #expect(state.connectivity.lastSyncAt == nil)
        #expect(state.connectivity.pendingUploads == 3)
        #expect(state.ownerUser.role == .customer)
    }

    @Test func roundTripPreservesShape() throws {
        let original = DeviceState(
            device: .init(
                id: "dev_1",
                label: "L",
                kind: .phoneNFC,
                ownerUserId: "u_1",
                siteId: nil,
                registeredAt: "2026-04-01T12:00:00.000Z",
                lastSeenAt: "2026-04-27T09:30:00.000Z"
            ),
            capabilities: [.scanner],
            kioskAllowed: false,
            ownerUser: .init(id: "u_1", role: .admin, displayName: "V"),
            settings: [
                "k": DeviceSettingValue(
                    value: .bool(true),
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    updatedBy: "ios-app"
                )
            ],
            scanStatus: .init(armed: false, pairingCode: nil, expiresAt: nil),
            pushToken: nil,
            connectivity: .init(
                online: true,
                lastSyncAt: nil,
                reconnectCount: 0,
                pendingUploads: 0
            )
        )

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(original)

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let decoded = try dec.decode(DeviceState.self, from: data)
        #expect(decoded == original)
    }

    @Test func syncRequestRoundTrip() throws {
        let req = SyncRequest(
            pendingSettings: [
                .init(
                    key: "device.label",
                    value: .string("New name"),
                    updatedAt: "2026-04-27T09:30:00.000Z"
                ),
                .init(
                    key: "notifications.scanRequest",
                    value: .bool(false),
                    updatedAt: "2026-04-27T09:30:00.000Z"
                ),
            ],
            diagnostics: .init(
                appVersion: "2.0.0",
                osVersion: "26.0",
                model: "iPhone15,2",
                pushPermission: .authorized,
                nfcAvailable: true,
                pendingUploads: 0,
                reconnectCount: 1
            )
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(req)
        let decoded = try JSONDecoder().decode(SyncRequest.self, from: data)
        #expect(decoded == req)

        // Also confirm the wire keys are camelCase as expected.
        let s = String(data: data, encoding: .utf8) ?? ""
        #expect(s.contains("\"pendingSettings\""))
        #expect(s.contains("\"pushPermission\""))
        #expect(s.contains("\"appVersion\""))
    }
}
