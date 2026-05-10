//
//  CustomerSignInProgressView.swift
//  ExpresScan
//
//  Plan B2 — phased status view shown while a customer sign-in is in
//  flight. The parent (`RootView`) drives the `phase` state; this view
//  is purely declarative. Layout matches the rest of the customer
//  surface (ChargerDetailView, ReadyView): tinted-glass `StatusHero`
//  inside a `ScrollView { LazyVStack {...} }` painted with
//  `.expressBackground()`.
//
//  The three step rows below the hero use `StatusPill` to mirror the
//  hero's tone, with a `LivePulseDot` on whichever step is currently
//  active. On failure we surface a "Try again" CTA that posts a
//  notification so the router can return to Welcome.
//

import SwiftUI

public struct CustomerSignInProgressView: View {

    public let phase: CustomerSignInPhase
    public let onTryAgain: () -> Void

    public init(
        phase: CustomerSignInPhase,
        onTryAgain: @escaping () -> Void
    ) {
        self.phase = phase
        self.onTryAgain = onTryAgain
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.xl) {
                hero
                stepRows
                if case .failure = phase {
                    PrimaryButton("Try again", action: onTryAgain)
                        .padding(.horizontal, Spacing.lg)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.xl)
        }
        .expressBackground()
        .animation(.easeInOut(duration: 0.25), value: stepIndex)
    }

    // MARK: - Hero

    private var hero: some View {
        StatusHero(
            state: heroState,
            title: heroTitle,
            secondary: heroSubtitle
        )
    }

    private var heroState: StatusHero.State {
        switch phase {
        case .confirming, .registering, .finalizing: return .reserved
        case .success: return .charging
        case .failure: return .outOfService
        }
    }

    private var heroTitle: String {
        switch phase {
        case .confirming: return "Checking your sign-in code"
        case .registering: return "Setting up this iPhone"
        case .finalizing: return "Almost there"
        case .success: return "You're signed in"
        case .failure: return "Couldn't sign in"
        }
    }

    private var heroSubtitle: String {
        switch phase {
        case .confirming: return "Just a moment…"
        case .registering: return "Almost there"
        case .finalizing: return "Signing you in"
        case .success: return "Welcome to ExpressCharge"
        case .failure(let message): return message
        }
    }

    // MARK: - Step rows

    private struct Step: Identifiable, Equatable {
        let id: Int
        let label: String
        let activeIcon: String
        let pendingIcon: String
        let doneIcon: String
    }

    private var steps: [Step] {
        [
            Step(
                id: 0,
                label: "Sign-in code",
                activeIcon: "magnifyingglass",
                pendingIcon: "circle.dashed",
                doneIcon: "checkmark.circle.fill"
            ),
            Step(
                id: 1,
                label: "Device setup",
                activeIcon: "iphone.gen3",
                pendingIcon: "circle.dashed",
                doneIcon: "checkmark.circle.fill"
            ),
            Step(
                id: 2,
                label: "Signing in",
                activeIcon: "person.crop.circle.badge.checkmark",
                pendingIcon: "circle.dashed",
                doneIcon: "checkmark.circle.fill"
            ),
        ]
    }

    /// 0-based index of the currently-active step (or the failed step,
    /// or `steps.count` for `.success`).
    private var stepIndex: Int {
        switch phase {
        case .confirming: return 0
        case .registering: return 1
        case .finalizing: return 2
        case .success: return steps.count
        case .failure: return -1
        }
    }

    @ViewBuilder
    private var stepRows: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(steps) { step in
                stepRow(for: step)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func stepRow(for step: Step) -> some View {
        let kind = rowKind(for: step.id)
        HStack(spacing: Spacing.sm) {
            StatusPill(
                label: step.label,
                systemImage: kind.icon(for: step),
                tone: kind.tone
            )
            if kind == .active {
                LivePulseDot(color: ColorPalette.info)
            }
            Spacer(minLength: 0)
        }
    }

    private enum RowKind: Equatable {
        case done
        case active
        case pending
        case failed

        var tone: StatusPill.Tone {
            switch self {
            case .done: return .positive
            case .active: return .info
            case .pending: return .neutral
            case .failed: return .negative
            }
        }

        func icon(for step: Step) -> String {
            switch self {
            case .done: return step.doneIcon
            case .active: return step.activeIcon
            case .pending: return step.pendingIcon
            case .failed: return "exclamationmark.triangle.fill"
            }
        }
    }

    private func rowKind(for index: Int) -> RowKind {
        if case .failure = phase { return index == 0 ? .failed : .pending }
        if case .success = phase { return .done }
        if index < stepIndex { return .done }
        if index == stepIndex { return .active }
        return .pending
    }
}

#if DEBUG
#Preview("Confirming") {
    CustomerSignInProgressView(phase: .confirming, onTryAgain: {})
}
#Preview("Registering") {
    CustomerSignInProgressView(phase: .registering, onTryAgain: {})
}
#Preview("Finalizing") {
    CustomerSignInProgressView(phase: .finalizing, onTryAgain: {})
}
#Preview("Success") {
    CustomerSignInProgressView(phase: .success, onTryAgain: {})
}
#Preview("Failure") {
    CustomerSignInProgressView(
        phase: .failure(message: "Connect to Wi-Fi or cellular and try again."),
        onTryAgain: {}
    )
}
#endif
