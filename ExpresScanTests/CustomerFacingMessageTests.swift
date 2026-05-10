//
//  CustomerFacingMessageTests.swift
//  ExpresScanTests
//
//  Verifies the central `APIError.customerFacingMessage(in:)` helper:
//  every APIError case maps to non-empty, non-jargon copy across every
//  context. Guards against accidental regressions where an HTTP code,
//  raw error name, or internal vocabulary leaks into a user-visible
//  string.
//

import Networking
import XCTest

@testable import ExpresScan

final class CustomerFacingMessageTests: XCTestCase {

    /// Substrings that must NEVER appear in customer-facing copy.
    /// Matched case-insensitively.
    private static let forbidden: [String] = [
        "401",
        "403",
        "404",
        "409",
        "410",
        "429",
        "5xx",
        "URLError",
        "APIError",
        "unauthorized",
        "forbidden",
        "ExpresSync",
        "rateLimited",
        "internal server",
    ]

    private static let allErrors: [APIError] = [
        .unauthorized,
        .forbidden,
        .notFound,
        .gone,
        .rateLimited,
        .network(),
        .network(detail: "URL -1009 offline"),
        .server(statusCode: 500, errorCode: nil),
        .server(statusCode: 502, errorCode: "bad_gateway"),
        .server(statusCode: 409, errorCode: nil),
        .decode(),
        .decode(detail: "keyNotFound(\"siteName\")"),
        .clockSkew,
        .invalidNonce,
    ]

    private static let allContexts: [ErrorContext] = [
        .signIn, .registration, .chargerLoad, .chargerDetailLoad,
        .chargerCommand, .reservationCancel, .signOut, .general,
    ]

    func testEveryErrorContextPairProducesNonEmptyNonJargonCopy() {
        for error in Self.allErrors {
            for context in Self.allContexts {
                let message = error.customerFacingMessage(in: context)
                XCTAssertFalse(
                    message.isEmpty,
                    "empty message for \(error) in \(context)"
                )
                let lowered = message.lowercased()
                for token in Self.forbidden {
                    XCTAssertFalse(
                        lowered.contains(token.lowercased()),
                        "leaked '\(token)' in '\(message)' for \(error) in \(context)"
                    )
                }
            }
        }
    }

    func testGenericPropertyMirrorsGeneralContext() {
        for error in Self.allErrors {
            XCTAssertEqual(
                error.customerFacingMessage,
                error.customerFacingMessage(in: .general)
            )
        }
    }

    // MARK: - Per-case spot checks (audit-flagged copy)

    func testSignInNotFoundNamesTheCardNotTheStatus() {
        let message = APIError.notFound.customerFacingMessage(in: .signIn)
        XCTAssertTrue(message.contains("don't recognise this card"))
    }

    func testCharger409ReadsAsChargerOfflineForCommandAndCancel() {
        let conflict = APIError.server(statusCode: 409, errorCode: nil)
        XCTAssertEqual(
            conflict.customerFacingMessage(in: .chargerCommand),
            "Charger offline"
        )
        XCTAssertEqual(
            conflict.customerFacingMessage(in: .reservationCancel),
            "Charger offline"
        )
    }

    func testChargerLoadDefaultMentionsChargersAndDetailMentionsDetails() {
        let decode = APIError.decode()
        XCTAssertTrue(
            decode.customerFacingMessage(in: .chargerLoad).contains("chargers")
        )
        XCTAssertTrue(
            decode.customerFacingMessage(in: .chargerDetailLoad)
                .contains("charger details")
        )
    }

    func testSignOutNetworkSuggestsTryingAgainWhenOnline() {
        let message = APIError.network().customerFacingMessage(in: .signOut)
        XCTAssertTrue(message.contains("when online"))
    }

    func testChargerListUnauthorizedSuggestsReSigningInToSeeChargers() {
        let message = APIError.unauthorized
            .customerFacingMessage(in: .chargerLoad)
        XCTAssertTrue(message.contains("Sign in again"))
        XCTAssertTrue(message.contains("chargers"))
    }

    func testChargerCommandDefaultDropsAwkwardCouldntAcceptCopy() {
        // Audit flagged the old copy as awkward; the new default reads
        // "The charger didn't accept the request. Try again."
        let message = APIError.decode().customerFacingMessage(in: .chargerCommand)
        XCTAssertTrue(message.contains("didn't accept the request"))
        XCTAssertFalse(message.contains("couldn't accept that command"))
    }

    // MARK: - Detail-equality + diagnostic surface (Phase 1 admin observability)

    func testNetworkAndDecodeEqualityIgnoresDetail() {
        XCTAssertEqual(APIError.network(), APIError.network(detail: "anything"))
        XCTAssertEqual(
            APIError.network(detail: "a"),
            APIError.network(detail: "b")
        )
        XCTAssertEqual(APIError.decode(), APIError.decode(detail: "x"))
        XCTAssertEqual(
            APIError.decode(detail: "a"),
            APIError.decode(detail: "b")
        )
        // Sanity: distinct cases still inequal.
        XCTAssertNotEqual(APIError.decode(), APIError.network())
    }

    func testDiagnosticDescriptionCarriesDetailWhenPresent() {
        XCTAssertEqual(APIError.unauthorized.diagnosticDescription, "HTTP 401 unauthorized")
        XCTAssertEqual(APIError.forbidden.diagnosticDescription, "HTTP 403 forbidden")
        XCTAssertEqual(APIError.gone.diagnosticDescription, "HTTP 410 gone")
        XCTAssertEqual(
            APIError.server(statusCode: 500, errorCode: "internal").diagnosticDescription,
            "HTTP 500 internal"
        )
        XCTAssertEqual(
            APIError.server(statusCode: 503, errorCode: nil).diagnosticDescription,
            "HTTP 503"
        )
        XCTAssertEqual(
            APIError.network(detail: "-1009 offline").diagnosticDescription,
            "Network: -1009 offline"
        )
        XCTAssertEqual(APIError.network().diagnosticDescription, "Network error")
        XCTAssertEqual(
            APIError.decode(detail: "keyNotFound(\"siteName\")").diagnosticDescription,
            "Decode: keyNotFound(\"siteName\")"
        )
        XCTAssertEqual(APIError.decode().diagnosticDescription, "Decode error")
    }

    func testGoneNudgesReSignInForChargerLoadButNotGenerally() {
        let listMessage = APIError.gone.customerFacingMessage(in: .chargerLoad)
        let generalMessage = APIError.gone.customerFacingMessage(in: .general)
        XCTAssertTrue(listMessage.contains("Sign in again"))
        XCTAssertFalse(generalMessage.contains("Sign in again"))
    }
}
