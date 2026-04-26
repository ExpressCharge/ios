//
//  ScanResultSignerTests.swift
//  CryptoTests
//
//  Known-vector tests for the HMAC-SHA256 scan-result signer. The vectors
//  in `Fixtures/hmac-vectors.json` are independently computed by the
//  Python snippet below — paste it into a python3 REPL to reproduce.
//
//  Reference snippet (Python 3.10+):
//  -----------------------------------
//      import hmac, hashlib, base64
//      secret_bytes = bytes(32)  # all-zero 32 bytes
//      msg = ("scan-result/v1|04AB12CDEF1234|X7R2KQ|"
//             "00000000-0000-0000-0000-000000000001|1745622000")
//      print(hmac.new(secret_bytes, msg.encode(), hashlib.sha256).hexdigest())
//      # → 2345bb48320f6a0f89953af9491569ba350e83e7e4c8ea136867ca6a5a648e1f
//  -----------------------------------
//
//  This file's vectors MUST stay byte-identical with
//  `expresscharge/tests/fixtures/hmac-vectors.json`. The Wave 3 verification
//  gate diffs the two files.
//

import Foundation
import Testing
@testable import Crypto

private struct Vector: Decodable {
    let deviceSecretBase64URL: String
    let idTag: String
    let pairingCode: String
    let deviceId: String
    let ts: Int64
    let expectedHex: String
}

private func loadVectors() throws -> [Vector] {
    guard let url = Bundle.module.url(
        forResource: "hmac-vectors",
        withExtension: "json"
    ) else {
        Issue.record("hmac-vectors.json not found in test bundle")
        return []
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode([Vector].self, from: data)
}

@Suite("ScanResultSigner")
struct ScanResultSignerTests {

    @Test("known vectors produce expected lowercase hex")
    func signsKnownVectors() throws {
        let vectors = try loadVectors()
        #expect(!vectors.isEmpty, "fixture file should contain at least one vector")

        for (index, vector) in vectors.enumerated() {
            let signer = try ScanResultSigner(
                deviceSecretBase64URL: vector.deviceSecretBase64URL
            )
            let actual = signer.sign(
                idTag: vector.idTag,
                pairingCode: vector.pairingCode,
                deviceId: vector.deviceId,
                ts: vector.ts
            )
            #expect(
                actual == vector.expectedHex,
                "vector \(index) mismatch (idTag=\(vector.idTag))"
            )
        }
    }

    @Test("init rejects invalid base64url")
    func initRejectsInvalidBase64URL() {
        #expect(throws: ScanResultSignerError.invalidBase64URL) {
            _ = try ScanResultSigner(deviceSecretBase64URL: "not!valid!base64url")
        }
    }

    @Test("init rejects empty secret")
    func initRejectsEmptySecret() {
        #expect(throws: ScanResultSignerError.emptyKey) {
            _ = try ScanResultSigner(deviceSecretBase64URL: "")
        }
    }

    @Test("signature is deterministic and lowercase hex")
    func signatureIsDeterministic() throws {
        let vectors = try loadVectors()
        let v = try #require(vectors.first)
        let signer = try ScanResultSigner(deviceSecretBase64URL: v.deviceSecretBase64URL)

        let a = signer.sign(idTag: v.idTag, pairingCode: v.pairingCode, deviceId: v.deviceId, ts: v.ts)
        let b = signer.sign(idTag: v.idTag, pairingCode: v.pairingCode, deviceId: v.deviceId, ts: v.ts)
        #expect(a == b, "HMAC must be deterministic")
        #expect(a.count == 64, "SHA-256 hex must be 64 chars")
        #expect(a == a.lowercased(), "must be lowercase hex")
    }

    @Test("changing any input changes signature")
    func changingInputChangesSignature() throws {
        let vectors = try loadVectors()
        let v = try #require(vectors.first)
        let signer = try ScanResultSigner(deviceSecretBase64URL: v.deviceSecretBase64URL)

        let base = signer.sign(idTag: v.idTag, pairingCode: v.pairingCode, deviceId: v.deviceId, ts: v.ts)
        let differentTs = signer.sign(idTag: v.idTag, pairingCode: v.pairingCode, deviceId: v.deviceId, ts: v.ts + 1)
        let differentDevice = signer.sign(idTag: v.idTag, pairingCode: v.pairingCode, deviceId: "other", ts: v.ts)
        let differentPairing = signer.sign(idTag: v.idTag, pairingCode: "other", deviceId: v.deviceId, ts: v.ts)
        let differentTag = signer.sign(idTag: "DEADBEEF", pairingCode: v.pairingCode, deviceId: v.deviceId, ts: v.ts)

        #expect(base != differentTs)
        #expect(base != differentDevice)
        #expect(base != differentPairing)
        #expect(base != differentTag)
    }
}
