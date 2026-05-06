//
//  LoginViewModelTests.swift
//  ExpresScanTests
//
//  Tests the static PKCE primitives owned by `LoginViewModel`. The
//  end-to-end ASWebAuthenticationSession flow (custom-scheme callback,
//  `expchg://register/callback?code=…` matched via the session's
//  `callbackURLScheme`) is covered by on-device manual QA; unit tests
//  can't exercise AuthServices without a real UIScene host. These
//  tests pin down the spec-compliance of the inputs we hand to
//  AuthServices.
//
//  Spec: `60-security.md` § 1 (PKCE) + `50-ios.md` § "Universal Links
//  + PKCE registration" (custom-scheme callback shape).
//

import XCTest
import CryptoKit
@testable import ExpresScan

@MainActor
final class LoginViewModelTests: XCTestCase {

    // MARK: - Code verifier

    func testGenerateCodeVerifierIs43Chars() {
        // RFC 7636 §4.1: base64url(32 random bytes) = 43 chars (no
        // padding). Anything else means we drifted off the spec.
        for _ in 0..<10 {
            let v = LoginViewModel.generateCodeVerifier()
            XCTAssertEqual(v.count, 43)
        }
    }

    func testGenerateCodeVerifierIsBase64URLAlphabet() {
        for _ in 0..<10 {
            let v = LoginViewModel.generateCodeVerifier()
            // base64url alphabet: A-Z a-z 0-9 - _
            // (no `+` or `/` and no `=` padding).
            XCTAssertNil(v.firstIndex(of: "+"))
            XCTAssertNil(v.firstIndex(of: "/"))
            XCTAssertNil(v.firstIndex(of: "="))
            for ch in v {
                let valid = ch.isLetter || ch.isNumber || ch == "-" || ch == "_"
                XCTAssertTrue(valid, "Unexpected char \(ch) in verifier")
            }
        }
    }

    func testGenerateCodeVerifierIsNotConstant() {
        // Five back-to-back calls should produce five different
        // verifiers. SecRandomCopyBytes makes a collision astronomically
        // unlikely.
        var seen = Set<String>()
        for _ in 0..<5 {
            seen.insert(LoginViewModel.generateCodeVerifier())
        }
        XCTAssertEqual(seen.count, 5)
    }

    // MARK: - Challenge

    func testComputeChallengeMatchesSHA256OfVerifier() {
        // RFC 7636 §4.2: code_challenge = base64url(SHA256(verifier)).
        let verifier = "test_verifier_xyz"
        let challenge = LoginViewModel.computeChallenge(verifier: verifier)

        let expectedDigest = SHA256.hash(data: Data(verifier.utf8))
        let expected = Data(expectedDigest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(challenge, expected)
    }

    func testComputeChallengeIsDeterministic() {
        let verifier = "stable_verifier"
        let a = LoginViewModel.computeChallenge(verifier: verifier)
        let b = LoginViewModel.computeChallenge(verifier: verifier)
        XCTAssertEqual(a, b)
    }
}
