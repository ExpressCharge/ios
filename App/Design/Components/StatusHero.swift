//
//  StatusHero.swift
//  ExpresScan
//
//  Wave 6 / Slice J — full-width tinted-glass hero card used by the
//  customer-style `ChargerDetailView`. Big SF Symbol + state title +
//  optional secondary line, tone-driven via `StatusPill.Tone`.
//
//  The card is _intentionally_ chunky — at AX5 the icon alone takes
//  ~140 px and the title can wrap. Always render inside a
//  `ScrollView { LazyVStack(...) }` so the layout never clips the
//  primary button below it.
//

import SwiftUI

public struct StatusHero: View {

    /// Logical state for the hero. Drives the SF Symbol + tint via
    /// `StatusPill.Tone`. Distinct from `ChargerSession.SessionState`
    /// because the hero collapses several wire states (e.g. `idle` and
    /// `preparing` both render as "Plugged in" tone-wise).
    public enum State: Equatable, Sendable {
        case idle
        case plugged
        case charging
        case reserved
        case outOfService

        var systemImage: String {
            switch self {
            case .idle: return "ev.charger"
            case .plugged: return "powerplug.fill"
            case .charging: return "bolt.fill"
            case .reserved: return "clock.fill"
            case .outOfService: return "exclamationmark.triangle.fill"
            }
        }

        var tone: StatusPill.Tone {
            switch self {
            case .idle: return .neutral
            case .plugged: return .info
            case .charging: return .positive
            case .reserved: return .info
            case .outOfService: return .warning
            }
        }
    }

    public let state: State
    public let title: String
    public let secondary: String?

    public init(state: State, title: String, secondary: String? = nil) {
        self.state = state
        self.title = title
        self.secondary = secondary
    }

    public var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: state.systemImage)
                .font(.system(size: 80, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(state.tone.fillColor)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
                .padding(.top, Spacing.sm)

            Text(title)
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(2)

            if let secondary {
                Text(secondary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .padding(.horizontal, Spacing.base)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .glassEffect(.regular.tint(state.tone.fillColor.opacity(0.15)))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if let secondary {
            return "\(title). \(secondary)"
        }
        return title
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 16) {
        StatusHero(state: .idle, title: "Idle", secondary: "Ready to charge")
        StatusHero(
            state: .reserved, title: "Reserved", secondary: "Reserved by Alice — Until 11:00")
        StatusHero(state: .charging, title: "Charging", secondary: nil)
        StatusHero(state: .outOfService, title: "Out of service")
    }
    .padding()
}
#endif
