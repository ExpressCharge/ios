//
//  SyncRequestLocationTests.swift
//  DeviceSyncTests
//
//  Phase 2 / Bundle 2a — round-trip the optional `location` field on
//  `SyncRequest`. Verifies:
//   - encode/decode preserves all four scalar fields exactly.
//   - omitting `location` round-trips as `nil` on the decoder side.
//   - the synthesized Codable does NOT drop the field when present.
//

import Foundation
import Testing

@testable import DeviceSync
@testable import Models

@Suite("SyncRequest — location round-trip")
struct SyncRequestLocationTests {

    private func makeDiagnostics() -> SyncRequest.Diagnostics {
        SyncRequest.Diagnostics(
            appVersion: "1.0.0 (1)",
            osVersion: "26.0",
            model: "iPhone",
            pushPermission: .notDetermined,
            nfcAvailable: true,
            pendingUploads: 0,
            reconnectCount: 0
        )
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    @Test func encodesAndDecodesLocation() throws {
        let captured = Date(timeIntervalSince1970: 1_715_000_000)
        let snap = LocationSnapshot(
            latitude: 37.7749,
            longitude: -122.4194,
            accuracyMeters: 12.5,
            capturedAt: captured
        )
        let body = SyncRequest(
            pendingSettings: [],
            diagnostics: makeDiagnostics(),
            location: snap
        )

        let data = try encoder.encode(body)
        let round = try decoder.decode(SyncRequest.self, from: data)

        #expect(round.location?.latitude == 37.7749)
        #expect(round.location?.longitude == -122.4194)
        #expect(round.location?.accuracyMeters == 12.5)
        #expect(round.location?.capturedAt == captured)
    }

    @Test func decodesNilLocationWhenAbsent() throws {
        // Body without a `location` key at all — older clients / older
        // server fixtures shape. Decoder must yield nil, not throw.
        let json = """
            {
              "pendingSettings": [],
              "diagnostics": {
                "appVersion": "1.0.0 (1)",
                "osVersion": "26.0",
                "model": "iPhone",
                "pushPermission": "notDetermined",
                "nfcAvailable": true,
                "pendingUploads": 0,
                "reconnectCount": 0
              }
            }
            """.data(using: .utf8)!

        let decoded = try decoder.decode(SyncRequest.self, from: json)
        #expect(decoded.location == nil)
    }

    @Test func decodesNilLocationWhenExplicitNull() throws {
        let json = """
            {
              "pendingSettings": [],
              "diagnostics": {
                "appVersion": "1.0.0 (1)",
                "osVersion": "26.0",
                "model": "iPhone",
                "pushPermission": "notDetermined",
                "nfcAvailable": true,
                "pendingUploads": 0,
                "reconnectCount": 0
              },
              "location": null
            }
            """.data(using: .utf8)!

        let decoded = try decoder.decode(SyncRequest.self, from: json)
        #expect(decoded.location == nil)
    }

    @Test func locationSnapshotEquality() {
        let a = LocationSnapshot(
            latitude: 1, longitude: 2, accuracyMeters: 3,
            capturedAt: Date(timeIntervalSince1970: 0)
        )
        let b = LocationSnapshot(
            latitude: 1, longitude: 2, accuracyMeters: 3,
            capturedAt: Date(timeIntervalSince1970: 0)
        )
        #expect(a == b)
    }
}
