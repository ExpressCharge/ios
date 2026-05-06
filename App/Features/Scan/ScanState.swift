//
//  ScanState.swift
//  ExpresScan
//
//  Single-source-of-truth enum for what the Scan feature is currently
//  doing. Mirrors the state-machine listing in `50-ios.md` § "State
//  machine" exactly.
//
//  The `ScanCoordinator` (E-app-wire) is the single `@Observable`
//  actor that holds a `var state: ScanState`. Views observe it and
//  switch on the case to render — there is one view per case (Ready /
//  ScanActive / Success / Error).
//

import Foundation
import Models

/// Errors the user might see in `.error(_)`. Each is a friendly,
/// recoverable failure mode — wireframes specify a unique copy +
/// SF Symbol per case.
public enum ScanError: Equatable, Sendable {
    /// 60 s with no card tap.
    case timeout
    /// MIFARE Classic, or any tag we deliberately reject.
    case unsupportedCard
    /// URLSession failure / SSE down / no internet.
    case network
    /// Pairing TTL elapsed before we could deliver the result.
    case pairingExpired
    /// Server returned 401 invalid_nonce or revoked.
    case tokenRevoked
    /// Catch-all: server 5xx with optional code.
    case server(code: String?)
}

/// `ScanState` is the union type the coordinator owns. Wave 4
/// (E-app-wire) owns transitions — this skeleton only declares the
/// shape so views in this track can compile against it.
public enum ScanState: Equatable, Sendable {
    /// Initial, no SSE yet. Covers cold launch.
    case idle
    /// SSE connection in flight (HTTP request opened, awaiting
    /// `event: connected`).
    case connecting
    /// SSE open, no active scan request.
    case readyToScan
    /// `event: scan.requested` arrived (or push was tapped). The
    /// payload is preserved so the active-scan UI can show the
    /// purpose / hint / countdown.
    case scanRequested(ScanRequest)
    /// `NFCTagReaderSession` is live.
    case scanning(ScanRequest)
    /// `POST /api/devices/scan-result` returned 200.
    case success(EnrichedScanResult)
    /// Recoverable error — shown until the user dismisses.
    case error(ScanError)
    /// SSE down + no recent push. Network reachability fallback.
    case offline
}
