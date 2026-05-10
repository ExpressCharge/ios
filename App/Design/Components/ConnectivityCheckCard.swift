//
//  ConnectivityCheckCard.swift
//  ExpresScan
//
//  Self-help diagnostic shown in Settings (customer + admin). Lets the
//  user verify each leg of the network round-trip works without a
//  technical readout: network reachable → server reachable → signed in →
//  sync succeeded. Each step renders as a row with a `StatusPill`; the
//  card's chrome tints to the overall state.
//
//  Steps run sequentially so a TLS / auth failure short-circuits later
//  steps as `.skipped`. Customers see this card in place of the
//  Diagnostics navigation link; admins see it alongside Diagnostics.
//

import Foundation
import Networking
import Observation
import SwiftUI

@MainActor
@Observable
public final class ConnectivityCheckViewModel {

    public enum OverallState: Equatable, Sendable {
        case idle
        case running
        case allPass
        case hasFailure
    }

    public enum StepID: String, CaseIterable, Sendable {
        /// DNS resolves the API host.
        case network
        /// HTTPS handshake to the API host returns a response (any status).
        case server
        /// `GET /api/devices/me` returns 2xx with a valid bearer.
        case auth
        /// `POST /api/devices/me/state/sync` round-trips successfully.
        case sync

        public var label: String {
            switch self {
            case .network: return "Network reachable"
            case .server: return "Server reachable"
            case .auth: return "Signed in"
            case .sync: return "Sync working"
            }
        }

        public var systemImage: String {
            switch self {
            case .network: return "wifi"
            case .server: return "server.rack"
            case .auth: return "person.badge.shield.checkmark"
            case .sync: return "arrow.triangle.2.circlepath"
            }
        }
    }

    public enum StepStatus: Equatable, Sendable {
        case pending
        case running
        case ok
        case skipped(reason: String)
        case fail(reason: String)

        public var pillTone: StatusPill.Tone {
            switch self {
            case .pending: return .neutral
            case .running: return .info
            case .ok: return .positive
            case .skipped: return .warning
            case .fail: return .negative
            }
        }

        public var pillIcon: String {
            switch self {
            case .pending: return "circle"
            case .running: return "arrow.triangle.2.circlepath"
            case .ok: return "checkmark.circle.fill"
            case .skipped: return "minus.circle"
            case .fail: return "xmark.octagon.fill"
            }
        }

        public var pillLabel: String {
            switch self {
            case .pending: return "Idle"
            case .running: return "Checking…"
            case .ok: return "OK"
            case .skipped: return "Skipped"
            case .fail: return "Failed"
            }
        }
    }

    public private(set) var overall: OverallState = .idle
    public private(set) var statuses: [StepID: StepStatus] = Dictionary(
        uniqueKeysWithValues: StepID.allCases.map { ($0, .pending) }
    )

    public init() {}

    public func reset() {
        overall = .idle
        for id in StepID.allCases { statuses[id] = .pending }
    }

    /// Run all four checks sequentially. A failure short-circuits later
    /// steps as `.skipped`. The view-model is a no-op while another
    /// run is in flight.
    public func run(
        api: APIClient,
        deviceState: DeviceStateCoordinator?
    ) async {
        guard overall != .running else { return }
        overall = .running
        for id in StepID.allCases { statuses[id] = .pending }

        // Step 1: network reachable (DNS resolution to API host).
        statuses[.network] = .running
        let host = api.baseURL.host ?? ""
        let networkOK: Bool
        if host.isEmpty {
            statuses[.network] = .fail(reason: "API host not configured")
            networkOK = false
        } else if await Self.canResolve(host: host) {
            statuses[.network] = .ok
            networkOK = true
        } else {
            statuses[.network] = .fail(
                reason: "Couldn't reach the network. Check Wi-Fi or cellular.")
            networkOK = false
        }

        // Step 2: server reachable (any HTTPS response from the API).
        if !networkOK {
            statuses[.server] = .skipped(reason: "Skipped — no network")
            statuses[.auth] = .skipped(reason: "Skipped — no network")
            statuses[.sync] = .skipped(reason: "Skipped — no network")
            overall = .hasFailure
            return
        }

        statuses[.server] = .running
        let serverOK = await Self.canHandshake(api: api)
        if serverOK {
            statuses[.server] = .ok
        } else {
            statuses[.server] = .fail(
                reason: "Couldn't reach the server. Try again in a moment.")
            statuses[.auth] = .skipped(reason: "Skipped — server unreachable")
            statuses[.sync] = .skipped(reason: "Skipped — server unreachable")
            overall = .hasFailure
            return
        }

        // Step 3: bearer auth works.
        statuses[.auth] = .running
        let authOK = await Self.canAuthenticate(api: api)
        if authOK {
            statuses[.auth] = .ok
        } else {
            statuses[.auth] = .fail(
                reason: "Sign in again to keep this iPhone connected.")
            statuses[.sync] = .skipped(reason: "Skipped — sign-in required")
            overall = .hasFailure
            return
        }

        // Step 4: sync round-trip. Sync is independent of APNs
        // registration — see DeviceStateCoordinator.syncOnce() for the
        // structured failure logs that explain *why* sync failed when
        // this step reports failure.
        statuses[.sync] = .running
        let result = await Self.canSync(coordinator: deviceState)
        switch result {
        case .ok:
            statuses[.sync] = .ok
        case .coordinatorUnavailable:
            statuses[.sync] = .fail(
                reason: "Device not ready. Reopen the app and try again.")
            overall = .hasFailure
            return
        case .failed:
            statuses[.sync] = .fail(
                reason: "Sync didn't finish. Try again in a moment.")
            overall = .hasFailure
            return
        }

        overall = .allPass
    }

    // MARK: - Step implementations

    private static func canResolve(host: String) async -> Bool {
        // Cheap DNS check — try a short HEAD request; URLSession handles
        // resolution + cache. Any non-throwing response (even 404) means
        // the host resolved.
        var request = URLRequest(url: URL(string: "https://\(host)")!)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        do {
            _ = try await URLSession.shared.data(for: request)
            return true
        } catch let error as URLError {
            // Resolution actually failed if we got `.cannotFindHost` or
            // `.notConnectedToInternet`; other errors still imply we
            // reached *something*.
            switch error.code {
            case .cannotFindHost, .notConnectedToInternet,
                .networkConnectionLost, .dnsLookupFailed:
                return false
            default:
                return true
            }
        } catch {
            return false
        }
    }

    private static func canHandshake(api: APIClient) async -> Bool {
        // We only care that the TLS handshake completed and the server
        // responded *at all*. An unauthenticated request to `/api/devices/me`
        // returns 401 — that's still a successful handshake.
        let endpoint = Endpoint(
            path: "/api/devices/me",
            method: .get,
            requiresAuth: false
        )
        do {
            _ = try await api.send(endpoint)
            return true
        } catch let api as APIError {
            switch api {
            case .network:
                return false
            default:
                // Server replied (incl. 401/403/5xx/decode) — handshake worked.
                return true
            }
        } catch {
            return false
        }
    }

    private static func canAuthenticate(api: APIClient) async -> Bool {
        let endpoint = Endpoint(path: "/api/devices/me", method: .get)
        do {
            let _: DeviceMeResponse = try await api.request(endpoint)
            return true
        } catch {
            return false
        }
    }

    private enum SyncCheckResult {
        case ok
        case coordinatorUnavailable
        case failed
    }

    private static func canSync(coordinator: DeviceStateCoordinator?) async -> SyncCheckResult {
        guard let coordinator else { return .coordinatorUnavailable }
        return await coordinator.syncOnce() ? .ok : .failed
    }
}

// MARK: - Card

public struct ConnectivityCheckCard: View {

    @Environment(\.app) private var app
    @Environment(RootCoordinator.self) private var coordinator
    @Bindable var viewModel: ConnectivityCheckViewModel

    /// Render WITHOUT the outer `cardSurface` so the parent can
    /// embed the check rows inline (e.g. inside `ConnectivityCard`
    /// in Settings, post-2026-05 UX merge of the two cards).
    private let inline: Bool

    public init(viewModel: ConnectivityCheckViewModel, inline: Bool = false) {
        self.viewModel = viewModel
        self.inline = inline
    }

    private func runCheck() async {
        await viewModel.run(api: app.api, deviceState: coordinator.deviceState)
    }

    public var body: some View {
        if inline {
            inlineBody
        } else {
            inlineBody
                .padding(Spacing.base)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(.tinted(overallTone))
        }
    }

    private var inlineBody: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if !inline {
                SectionHeader("Connectivity check") {
                    overallPill
                }
            } else {
                HStack {
                    Text("Self-test")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    overallPill
                }
            }

            VStack(spacing: Spacing.sm) {
                ForEach(ConnectivityCheckViewModel.StepID.allCases, id: \.self) { id in
                    StepRow(
                        id: id,
                        status: viewModel.statuses[id] ?? .pending
                    )
                }
            }

            actionButton
        }
    }

    private var overallTone: StatusPill.Tone {
        switch viewModel.overall {
        case .idle: return .neutral
        case .running: return .info
        case .allPass: return .positive
        case .hasFailure: return .negative
        }
    }

    @ViewBuilder
    private var overallPill: some View {
        switch viewModel.overall {
        case .idle:
            StatusPill(label: "Not run", systemImage: "circle", tone: .neutral)
        case .running:
            HStack(spacing: Spacing.xs) {
                LivePulseDot(color: ColorPalette.info, size: 6)
                StatusPill(
                    label: "Running",
                    systemImage: "arrow.triangle.2.circlepath",
                    tone: .info
                )
            }
        case .allPass:
            StatusPill(
                label: "All checks passed",
                systemImage: "checkmark.seal.fill",
                tone: .positive
            )
        case .hasFailure:
            StatusPill(
                label: "Issues found",
                systemImage: "exclamationmark.triangle.fill",
                tone: .negative
            )
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch viewModel.overall {
        case .idle:
            PrimaryButton(
                "Run connectivity check",
                systemImage: "antenna.radiowaves.left.and.right",
                action: { Task { await runCheck() } }
            )
        case .running:
            PrimaryButton(
                "Checking…",
                state: .loading,
                action: {}
            )
        case .allPass:
            PrimaryButton(
                "Run again",
                systemImage: "arrow.clockwise",
                action: {
                    Task {
                        viewModel.reset()
                        await runCheck()
                    }
                }
            )
        case .hasFailure:
            PrimaryButton(
                "Retry",
                systemImage: "arrow.clockwise",
                action: {
                    Task {
                        viewModel.reset()
                        await runCheck()
                    }
                }
            )
        }
    }
}

private struct StepRow: View {
    let id: ConnectivityCheckViewModel.StepID
    let status: ConnectivityCheckViewModel.StepStatus

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: id.systemImage)
                .frame(width: 24)
                .foregroundStyle(ColorPalette.primaryCyan)

            VStack(alignment: .leading, spacing: 2) {
                Text(id.label).font(.subheadline.weight(.medium))
                if case .fail(let reason) = status {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if case .skipped(let reason) = status {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if case .running = status {
                ProgressView().controlSize(.small)
            } else {
                StatusPill(
                    label: status.pillLabel,
                    systemImage: status.pillIcon,
                    tone: status.pillTone
                )
            }
        }
    }
}
