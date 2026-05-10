//
//  CustomerSignInMethod.swift
//  ExpresScan
//
//  Plan B2 — types for the customer sign-in progress UX. The router
//  drops the app into `RootRoute.customerSigningIn(method:phase:)` and
//  the progress view renders the matching state. The split between
//  "method" (where the credential came from) and "phase" (how far the
//  network round-trip got) keeps both concerns independently testable
//  and lets future methods (NFC tap) reuse the same view.
//

import Foundation

/// The credential channel a customer used to start the sign-in flow.
/// QR code + magic email are wired today; NFC tap is reserved for a
/// future iteration so the route signature doesn't have to change.
public enum CustomerSignInMethod: Sendable, Equatable {
    case qrCode(publicId: String)
    case magicEmail(token: String)
    case nfcTap
}

/// Phases of the customer sign-in pipeline. The view-model advances
/// through these in order on the success path; on failure it jumps to
/// `.failure(message:)` with a user-facing message produced via the
/// `customerFacingMessage` helper (or the local fallback below).
public enum CustomerSignInPhase: Sendable, Equatable {
    /// Network round-trip in flight: POSTing the credential and
    /// awaiting a `{device, token, user}` response.
    case confirming
    /// Server replied OK — device row was created, we're processing
    /// the response on-device.
    case registering
    /// Keychain write + coordinator bootstrap.
    case finalizing
    /// Brief flash before the route flips to `.ready`.
    case success
    /// Terminal failure with a customer-facing message. The view
    /// surfaces a "Try again" CTA that returns the user to Welcome.
    case failure(message: String)
}
