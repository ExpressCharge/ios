//
//  PowerFormatting.swift
//  ExpresScan
//
//  Shared kW formatter. Preserves one decimal place but trims a
//  trailing `.0` so whole-number ratings read cleanly:
//    7.68 → "7.7", 11.0 → "11", 7.0 → "7", 11.5 → "11.5".
//
//  Never rounds to integers — a 7.68 kW charger should not display as
//  "8 kW", since users compare these values against onboard charger
//  specs (32A × 240V = 7.68 kW; rounding loses real information).
//

import Foundation

/// Format a kW value with up to one decimal place, trimming trailing
/// `.0`. Mirrors the server's `formatKw` in `src/lib/utils/format.ts`.
func formatKW(_ kw: Double) -> String {
    let rounded = (kw * 10).rounded() / 10
    if rounded == rounded.rounded() {
        return String(format: "%.0f", rounded)
    }
    return String(format: "%.1f", rounded)
}

/// Single-phase 240V derivation. Mirrors the existing logic in
/// `ChargerSession+DerivedAmps.swift` so list rows can show
/// "32A · 7.7 kW" without plumbing an amperage field through the
/// charger list response.
func derivedAmps(fromKW kw: Double) -> Int? {
    guard kw.isFinite, kw > 0 else { return nil }
    return Int((kw * 1000.0 / 240.0).rounded())
}
