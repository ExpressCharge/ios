//
//  CustomerFacingMessage.swift
//  ExpresScan
//
//  Central error → customer-friendly string mapper. Strips HTTP codes,
//  raw error names, and internal vocabulary so a non-technical user sees
//  copy they can act on.
//
//  The mapper is intentionally context-aware: the same `APIError.notFound`
//  reads differently when surfaced from a sign-in flow versus a charger
//  command. Per-VM wrappers (`QrSignInViewModel.message(for:)`,
//  `ChargerListViewModel.message(for:)`, etc.) call this helper with the
//  appropriate `ErrorContext` rather than maintaining their own switch
//  statements.
//

import Foundation
import Networking

/// The surface a customer-facing error originated from. Drives both the
/// per-case overrides and the default fallback copy.
public enum ErrorContext: Sendable, Equatable {
    /// QR / magic-email / future tap-to-login flows.
    case signIn
    /// PKCE device registration (admin), and any future
    /// device-registration error path.
    case registration
    /// Loading the charger list (top-of-tab refresh).
    case chargerLoad
    /// Loading a single charger's detail page.
    case chargerDetailLoad
    /// Issuing a start/stop command to a charger.
    case chargerCommand
    /// Cancelling a reservation.
    case reservationCancel
    /// Signing out via DELETE /api/devices/{id}.
    case signOut
    /// Anything else.
    case general
}

extension APIError {

    /// Customer-friendly message in the generic context. Equivalent to
    /// `customerFacingMessage(in: .general)`.
    public var customerFacingMessage: String {
        customerFacingMessage(in: .general)
    }

    /// Customer-friendly message tailored to where the error appears.
    public func customerFacingMessage(in context: ErrorContext) -> String {
        switch (self, context) {

        // ---- Charger-specific 409 ------------------------------------
        case (.server(409, _), .chargerCommand),
            (.server(409, _), .reservationCancel):
            return "Charger offline"

        // ---- notFound (widely overloaded) ----------------------------
        case (.notFound, .signIn):
            return "We don't recognise this card. Check the QR isn't damaged."
        case (.notFound, .chargerCommand):
            return "Charger not found."
        case (.notFound, .reservationCancel):
            return "Reservation already gone."

        // ---- unauthorized (401) --------------------------------------
        case (.unauthorized, .chargerLoad):
            return "Sign in again to see chargers."
        case (.unauthorized, _):
            return "Sign in again."

        // ---- forbidden (403) -----------------------------------------
        case (.forbidden, .chargerLoad):
            return "You don't have access to manage chargers."
        case (.forbidden, _):
            return "Access denied."

        // ---- gone (410) ----------------------------------------------
        case (.gone, .chargerLoad):
            return "This iPhone was deregistered. Sign in again."
        case (.gone, _):
            return "This iPhone was deregistered."

        // ---- rateLimited (429) ---------------------------------------
        case (.rateLimited, .signIn):
            return "Too many sign-in attempts. Wait a minute and try again."
        case (.rateLimited, _):
            return "Too many attempts. Wait a minute and try again."

        // ---- network (transport-layer) -------------------------------
        case (.network, .signIn):
            return "Connect to Wi-Fi or cellular and try again."
        case (.network, .chargerLoad):
            return "Connect to Wi-Fi or cellular and pull to refresh."
        case (.network, .chargerDetailLoad):
            return "Connect to Wi-Fi or cellular and try again."
        case (.network, .chargerCommand):
            return "Couldn't reach the server. Try again."
        case (.network, .signOut):
            return "Couldn't reach the server. Try again when online."
        case (.network, _):
            return "Connect to Wi-Fi or cellular and try again."

        // ---- everything else falls back to the per-context default --
        default:
            return Self.defaultCopy(for: context)
        }
    }

    private static func defaultCopy(for context: ErrorContext) -> String {
        switch context {
        case .signIn:
            return "Couldn't sign in. Try scanning again."
        case .registration:
            return "Something went wrong. Please try again."
        case .chargerLoad:
            return "Couldn't load chargers. Try again."
        case .chargerDetailLoad:
            return "Couldn't load charger details."
        case .chargerCommand:
            return "The charger didn't accept the request. Try again."
        case .reservationCancel:
            return "Couldn't cancel reservation. Try again."
        case .signOut:
            return "Couldn't complete sign-out. Try again when online."
        case .general:
            return "Something went wrong. Please try again."
        }
    }
}
