//
//  AuthTests.swift
//  ExpresScanTests
//
//  Coverage for the customer sign-in plumbing added in plan B2:
//   - `MagicEmailDeepLinkHandler.parse` (URL parsing edge cases)
//   - `CustomerSignInMethod` / `CustomerSignInPhase` (equality + payload
//     extraction)
//
//  These types are defence-in-depth boundary code: the deep-link parser
//  is the first thing that touches a hostile URL, and the phase enum
//  drives the UI state machine that surfaces failure copy. Both want
//  pinned tests so future copy/host changes can't silently break the
//  customer sign-in flow.
//

import XCTest

@testable import ExpresScan

final class MagicEmailDeepLinkHandlerTests: XCTestCase {

    // MARK: - Happy paths

    func testParseAcceptsCanonicalCustomerHostUrl() {
        let url = URL(string: "https://example.com/m/AbCd-1234_xyz")!
        XCTAssertEqual(
            MagicEmailDeepLinkHandler.parse(url),
            "AbCd-1234_xyz"
        )
    }

    func testParseAcceptsMinimumLengthToken() {
        let url = URL(string: "https://example.com/m/12345678")!
        XCTAssertEqual(MagicEmailDeepLinkHandler.parse(url), "12345678")
    }

    func testParseAcceptsLongToken() {
        let token = String(repeating: "Ab9_", count: 16)  // 64 chars
        let url = URL(string: "https://example.com/m/\(token)")!
        XCTAssertEqual(MagicEmailDeepLinkHandler.parse(url), token)
    }

    // MARK: - Rejections

    func testParseRejectsTokenShorterThanEightChars() {
        let url = URL(string: "https://example.com/m/short")!
        XCTAssertNil(MagicEmailDeepLinkHandler.parse(url))
    }

    func testParseRejectsNonUrlSafeCharacters() {
        // Spaces, slashes, %-encoded slashes — none of these are
        // URL-safe per the parser's rule.
        let urls = [
            "https://example.com/m/has spaces ok",
            "https://example.com/m/has/slash/path",
            "https://example.com/m/star*char",
        ]
        for raw in urls {
            let url = URL(string: raw)!
            XCTAssertNil(
                MagicEmailDeepLinkHandler.parse(url),
                "expected nil for \(raw)"
            )
        }
    }

    func testParseRejectsAdminHost() {
        // The admin host is `manage.example.com`; magic-email links
        // must come from the customer host.
        let url = URL(string: "https://manage.example.com/m/12345678")!
        XCTAssertNil(MagicEmailDeepLinkHandler.parse(url))
    }

    func testParseRejectsHttpScheme() {
        // HTTPS only — refuse to follow a downgrade.
        let url = URL(string: "http://example.com/m/12345678")!
        XCTAssertNil(MagicEmailDeepLinkHandler.parse(url))
    }

    func testParseRejectsCustomScheme() {
        // `expchg://` is the ASWebAuthenticationSession scheme; not a
        // magic-link channel.
        let url = URL(string: "expchg://example.com/m/12345678")!
        XCTAssertNil(MagicEmailDeepLinkHandler.parse(url))
    }

    func testParseRejectsWrongPathPrefix() {
        // `/u/` is the QR-card path; `/c/` is the charger sticker path.
        // Neither belongs to the magic-email channel.
        let urlU = URL(string: "https://example.com/u/12345678")!
        let urlC = URL(string: "https://example.com/c/12345678")!
        XCTAssertNil(MagicEmailDeepLinkHandler.parse(urlU))
        XCTAssertNil(MagicEmailDeepLinkHandler.parse(urlC))
    }

    func testParseRejectsBareHostNoPath() {
        let url = URL(string: "https://example.com")!
        XCTAssertNil(MagicEmailDeepLinkHandler.parse(url))
    }

    func testParseRejectsEmptyTokenSegment() {
        // `/m/` with no token after the slash.
        let url = URL(string: "https://example.com/m/")!
        XCTAssertNil(MagicEmailDeepLinkHandler.parse(url))
    }

    // MARK: - Direct token validator

    func testValidatedTokenAcceptsAllUrlSafeAlphabetChars() {
        let alphabet =
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        XCTAssertEqual(
            MagicEmailDeepLinkHandler.validatedToken(alphabet),
            alphabet
        )
    }

    func testValidatedTokenRejectsEmptyAndShort() {
        XCTAssertNil(MagicEmailDeepLinkHandler.validatedToken(""))
        XCTAssertNil(MagicEmailDeepLinkHandler.validatedToken("1234567"))
    }
}

final class CustomerSignInPhaseTests: XCTestCase {

    func testEquality() {
        XCTAssertEqual(CustomerSignInPhase.confirming, .confirming)
        XCTAssertEqual(CustomerSignInPhase.registering, .registering)
        XCTAssertEqual(CustomerSignInPhase.finalizing, .finalizing)
        XCTAssertEqual(CustomerSignInPhase.success, .success)
        XCTAssertEqual(
            CustomerSignInPhase.failure(message: "x"),
            .failure(message: "x")
        )
        XCTAssertNotEqual(
            CustomerSignInPhase.failure(message: "x"),
            .failure(message: "y")
        )
        XCTAssertNotEqual(
            CustomerSignInPhase.confirming, .registering)
    }

    func testFailureMessageExtraction() {
        let phase: CustomerSignInPhase = .failure(message: "Network error")
        if case .failure(let extracted) = phase {
            XCTAssertEqual(extracted, "Network error")
        } else {
            XCTFail("expected .failure phase")
        }
    }
}

final class CustomerSignInMethodTests: XCTestCase {

    func testEqualityAcrossDistinctPayloads() {
        XCTAssertEqual(
            CustomerSignInMethod.qrCode(publicId: "ABCDEFGH"),
            .qrCode(publicId: "ABCDEFGH")
        )
        XCTAssertNotEqual(
            CustomerSignInMethod.qrCode(publicId: "ABCDEFGH"),
            .qrCode(publicId: "ZYXWVUTS")
        )
        XCTAssertEqual(
            CustomerSignInMethod.magicEmail(token: "tk-1"),
            .magicEmail(token: "tk-1")
        )
        XCTAssertNotEqual(
            CustomerSignInMethod.magicEmail(token: "tk-1"),
            .magicEmail(token: "tk-2")
        )
        XCTAssertEqual(CustomerSignInMethod.nfcTap, .nfcTap)
        XCTAssertNotEqual(
            CustomerSignInMethod.qrCode(publicId: "X"),
            .magicEmail(token: "X")
        )
    }
}
