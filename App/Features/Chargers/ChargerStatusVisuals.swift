//
//  ChargerStatusVisuals.swift
//  ExpresScan
//
//  Single-source mapping from a charger's logical state to the iOS
//  design tokens used by the list, detail hero, and connector glyphs.
//  Mirrors `expresscharge/islands/shared/device-visuals.ts` so the iOS
//  surfaces never drift from the web admin.
//

import SwiftUI

enum ChargerStatusVisuals {

    /// Coarse-grained status used to pick a tone. Collapses both
    /// `ChargerListEntry.ChargerState` and `StatusHero.State` into a
    /// single semantic shape.
    enum Status: Equatable, Sendable {
        case available     // idle / preparing / plugged
        case charging
        case reserved
        case unavailable   // out-of-service (faulted / unavailable)
        case offline
    }

    /// Status color used for icon halos, status pills, and the
    /// active-card tint. Values mirror the web's `device-visuals.ts`
    /// (`STATUS_HALO`): azure available, green charging, amber for
    /// both reserved + unavailable, red for offline + faulted.
    static func tone(for status: Status) -> Color {
        switch status {
        case .available:   return ColorPalette.primaryCyan
        case .charging:    return ColorPalette.voltGreen
        case .reserved:    return ColorPalette.warningAmber
        case .unavailable: return ColorPalette.warningAmber
        case .offline:     return ColorPalette.destructiveRose
        }
    }

    /// Soft outer-glow colour used by `ChargerHero` and the active
    /// session card. Falls back to the same hue at a lower opacity for
    /// statuses without a dedicated glow asset.
    static func glow(for status: Status) -> Color {
        switch status {
        case .charging:  return ColorPalette.glowGreen
        case .available: return ColorPalette.glowCyan
        default:         return tone(for: status).opacity(0.5)
        }
    }

    /// Map the wire-level `ChargerState` to a coarse status.
    static func status(from state: ChargerListEntry.ChargerState) -> Status {
        switch state {
        case .idle, .preparing: return .available
        case .charging:         return .charging
        case .reserved:         return .reserved
        case .outOfService:     return .unavailable
        case .offline:          return .offline
        }
    }

    /// Map the detail-hero state (which already collapses idle+plugged)
    /// to a coarse status. The `isOffline` override is needed because
    /// the hero state collapses offline into `.outOfService`.
    static func status(
        for hero: StatusHero.State,
        isOffline: Bool
    ) -> Status {
        if isOffline { return .offline }
        switch hero {
        case .idle, .plugged: return .available
        case .charging:       return .charging
        case .reserved:       return .reserved
        case .outOfService:   return .unavailable
        }
    }
}
