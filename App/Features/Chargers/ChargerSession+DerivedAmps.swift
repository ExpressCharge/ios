//
//  ChargerSession+DerivedAmps.swift
//  ExpresScan
//
//  The wire model carries kW but not amps. The active session card
//  shows amperage as a derived value, assuming a 240 V single-phase
//  circuit (the dominant residential / light-commercial Wallbox
//  topology). When future hardware ships true 3-phase 400 V, this
//  helper is the single place to extend.
//

import Foundation

extension ChargerSession {

    /// Whole-amps current draw. Prefers the server-derived `amps`
    /// field; falls back to a client-side computation from `kw` for
    /// older server builds that don't ship the field. Returns nil when
    /// the session has no live kW reading yet.
    public var derivedAmps: Int? {
        if let amps { return amps }
        guard let kw, kw.isFinite, kw > 0 else { return nil }
        return Int((kw * 1000.0 / 240.0).rounded())
    }
}
