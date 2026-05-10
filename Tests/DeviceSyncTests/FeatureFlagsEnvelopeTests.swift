//
//  FeatureFlagsEnvelopeTests.swift
//  DeviceSyncTests
//
//  Coverage for the `flags` field on the `DeviceState` envelope. The
//  field is optional on the wire (default-omit, omitted entirely for
//  charger-kind devices) and decodes to `[:]` when missing.
//

import Foundation
import Testing

@testable import DeviceSync
@testable import Models

@Suite("DeviceState — flags wire")
struct FeatureFlagsEnvelopeTests {

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func envelopeJSON(flagsBlock: String?) -> String {
        let flagsLine =
            flagsBlock.map { ",\n              \"flags\": \($0)" } ?? ""
        return """
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
              "settings": {}\(flagsLine),
              "connectivity": {
                "online": true,
                "lastSyncAt": null,
                "reconnectCount": 0,
                "pendingUploads": 0
              }
            }
            """
    }

    @Test func decodesEnvelopeWithFlagsPresent() throws {
        let block = """
            {
                "ui.experimental_panel": {
                  "value": true,
                  "updatedAt": "2026-05-01T12:00:00Z",
                  "updatedBy": "admin"
                },
                "scan.batch_size": {
                  "value": 5,
                  "updatedAt": "2026-05-01T12:01:00Z",
                  "updatedBy": "admin"
                }
              }
            """
        let data = Data(envelopeJSON(flagsBlock: block).utf8)
        let state = try decoder().decode(DeviceState.self, from: data)
        #expect(state.flags.count == 2)
        if case .bool(let b) = state.flags["ui.experimental_panel"]?.value {
            #expect(b == true)
        } else {
            Issue.record("expected bool value for ui.experimental_panel")
        }
        if case .int(let i) = state.flags["scan.batch_size"]?.value {
            #expect(i == 5)
        } else {
            Issue.record("expected int value for scan.batch_size")
        }
    }

    @Test func decodesEnvelopeWithFlagsAbsent() throws {
        let data = Data(envelopeJSON(flagsBlock: nil).utf8)
        let state = try decoder().decode(DeviceState.self, from: data)
        #expect(state.flags.isEmpty)
    }

    @Test func decodesEnvelopeWithFlagsEmptyObject() throws {
        let data = Data(envelopeJSON(flagsBlock: "{}").utf8)
        let state = try decoder().decode(DeviceState.self, from: data)
        #expect(state.flags.isEmpty)
    }
}
