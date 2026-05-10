//
//  ChargerDetailViewModel.swift
//  ExpresScan
//
//  Wave 6 / Slice J + Slice S — owns the customer-style charger detail
//  screen. Drives session + reservations bootstrap (parallel-fetch via
//  `async let`), Start (Path A: auto-resolved customer from active
//  reservation, no picker; Path B: customer picker), Stop, and per-row
//  reservation cancel.
//
//  All public methods stay on the main actor — `@MainActor` is applied
//  at the class level so VM mutations are safe to read from the view
//  body. `Loadable.error(message)` is a pre-formatted, user-facing
//  string (the view just renders it).
//

import Foundation
import Networking
import Observation

@MainActor
@Observable
public final class ChargerDetailViewModel {

    /// Mirrors the standard four-state load enum used elsewhere
    /// (Registration / ChargerListVM). `.error` carries a user-facing
    /// message; the view renders it verbatim.
    public enum Loadable: Equatable, Sendable {
        case idle
        case loading
        case ok
        /// `message` is the customer-friendly copy; `raw` carries the
        /// underlying `APIError` for the admin-only diagnostic block.
        case error(message: String, raw: APIError?)
    }

    // MARK: - Inputs

    public let entry: ChargerListEntry

    // MARK: - State

    public private(set) var session: ChargerSession?
    public private(set) var reservations: [Reservation] = []
    /// Slice S — customer list for Path B picker. Lazy-loaded.
    public private(set) var customers: [CustomerOption] = []
    public private(set) var loadState: Loadable = .idle
    public private(set) var actionInFlight: Bool = false
    public var pickerVisible: Bool = false

    // MARK: - Dependencies

    private let api: APIClient
    private let now: @Sendable () -> Date

    public init(
        entry: ChargerListEntry,
        api: APIClient,
        now: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.entry = entry
        self.api = api
        self.now = now
    }

    // MARK: - Derived

    /// The reservation whose `[startsAt, endsAt)` window covers `now`.
    /// Drives the "Start charging (Customer)" CTA label and the
    /// auto-bound idTag for Path A.
    public var currentReservation: Reservation? {
        let n = now()
        return reservations.first { $0.covers(n) }
    }

    /// Hero state derived from the wire `session.state` + the active
    /// reservation. The view consumes this so the hero/CTA copy stay in
    /// sync without duplicating the rule everywhere.
    public var heroState: StatusHero.State {
        if let s = session?.state {
            switch s {
            case .charging: return .charging
            case .preparing: return .plugged
            case .stopping: return .charging
            case .outOfService: return .outOfService
            case .idle:
                return currentReservation != nil ? .reserved : .idle
            }
        }
        // Fall back to the row state until `session` loads. Unmanaged
        // chargers (Track W7) ship no state — treat as idle so the
        // hero doesn't render an "offline" badge.
        switch entry.state ?? .idle {
        case .charging: return .charging
        case .preparing: return .plugged
        case .reserved: return .reserved
        case .outOfService: return .outOfService
        case .offline: return .outOfService
        case .idle:
            return currentReservation != nil ? .reserved : .idle
        }
    }

    public var isCharging: Bool {
        session?.state == .charging || session?.state == .stopping
    }

    public var isOffline: Bool {
        // Unmanaged chargers don't ship a state — they're physically
        // present and usable, so treat absence-of-state as not-offline.
        entry.state == .offline
    }

    /// High-level availability of the charger for user actions. Drives
    /// whether the detail screen renders the reservations card +
    /// start/stop CTA (`.ready`) or replaces them with an explanatory
    /// notice (`.offline` / `.outOfService`) or the "just plug in"
    /// instructions (`.dumbCharger` — Migration 0043).
    public enum Availability: Equatable, Sendable {
        case ready
        case offline
        case outOfService
        case dumbCharger
    }

    public var availability: Availability {
        // `.dumbCharger` wins over every transient network state.
        // `managementMode` is a static property of the charger row — an
        // unmanaged charger should NEVER surface OCPP CTAs even if it
        // momentarily reports an OCPP-flavoured state.
        if entry.managementMode == .unmanaged { return .dumbCharger }
        if isOffline { return .offline }
        if heroState == .outOfService { return .outOfService }
        return .ready
    }

    /// Connectors associated with this charger. The wire model only
    /// reports the one connector type the row already knows about,
    /// so for now this is a single-element list — sized as a
    /// collection so `ChargerHero` can grow to multi-connector
    /// hardware without re-plumbing.
    public struct ConnectorDescriptor: Equatable, Sendable {
        public let connectorType: ChargerListEntry.ConnectorType?
        public let maxKw: Double?
    }

    public var connectors: [ConnectorDescriptor] {
        [ConnectorDescriptor(connectorType: entry.connectorType, maxKw: entry.maxKw)]
    }

    // MARK: - Public methods

    /// Initial bootstrap — parallel-load `session` + `reservations`.
    /// Idempotent: re-entrant calls while loading short-circuit.
    /// Unmanaged chargers (Migration 0043) skip every load: they don't
    /// have sessions or reservations and the endpoints would 404 anyway.
    public func bootstrap() async {
        if case .loading = loadState { return }
        if entry.managementMode == .unmanaged {
            loadState = .ok
            return
        }
        loadState = .loading
        await loadSessionAndReservations()
    }

    /// Pull-to-refresh entry point; same shape as bootstrap but
    /// re-runs even if a previous load errored.
    public func refresh() async {
        if entry.managementMode == .unmanaged {
            loadState = .ok
            return
        }
        loadState = .loading
        await loadSessionAndReservations()
    }

    /// Start charging. Two paths:
    ///   - **A:** charger has an active reservation that carries a
    ///     `lagoCustomerExternalId` → synthesize a minimal
    ///     `CustomerOption` straight from the reservation and call
    ///     `submitStart(customer:)` directly. No picker, no extra round
    ///     trip — the server resolves `OCPP-{externalId}` server-side.
    ///     If the reservation lacks an externalId (older server, or a
    ///     blackout), fall through to Path B.
    ///   - **B:** unreserved → open the customer picker; the picker's
    ///     `onPick` calls `submitStart(customer:)` once the operator picks.
    public func startCharging() async {
        guard !actionInFlight else { return }
        if let res = currentReservation, let extId = res.lagoCustomerExternalId {
            // Path A: synthesize the minimum CustomerOption needed to
            // submit. The server doesn't read any other field for the
            // resolution; the rest are set sensibly so the optimistic
            // session flip below renders cleanly.
            let synthesized = CustomerOption(
                lagoCustomerExternalId: extId,
                userId: "",
                displayName: res.customerLabel ?? extId,
                name: res.customerLabel,
                email: nil,
                isOwn: false,
                lastUsedAt: nil
            )
            await submitStart(customer: synthesized)
            return
        }
        // Path B: load customers lazily before showing the picker.
        await ensureCustomersLoaded()
        pickerVisible = true
    }

    /// Submit the actual remote-start. Called from Path A directly and
    /// from Path B when the picker resolves.
    public func submitStart(customer: CustomerOption) async {
        guard !actionInFlight else { return }
        actionInFlight = true
        defer { actionInFlight = false }

        let body = StartBody(
            lagoCustomerExternalId: customer.lagoCustomerExternalId,
            reservationId: currentReservation?.reservationId
        )
        let endpoint = Endpoint.with(
            path: "/api/admin/devices/\(entry.chargerId)/start",
            method: .post,
            body: body
        )
        do {
            try await api.send(endpoint)
            // Optimistic flip → preparing; real session lands on the
            // next refresh. We don't know the resolved idTag client-side
            // (it's `OCPP-{externalId}`, but we leave that to the server
            // confirmation) so we leave it nil here.
            session = ChargerSession(
                chargerId: entry.chargerId,
                state: .preparing,
                idTag: nil,
                customerName: customer.displayName
            )
            // Refresh shortly after so kwh/kw/elapsed catch up.
            await loadSessionAndReservations()
        } catch let error as APIError {
            loadState = .error(message: messageForStartStop(error), raw: error)
        } catch {
            loadState = .error(message: "Couldn't start charging. Try again.", raw: nil)
        }
    }

    /// Stop charging. The View owns the confirmation dialog; the VM
    /// only fires when `confirmed: true`.
    public func stopCharging(confirmed: Bool) async {
        guard confirmed, !actionInFlight else { return }
        actionInFlight = true
        defer { actionInFlight = false }

        let endpoint = Endpoint.with(
            path: "/api/admin/devices/\(entry.chargerId)/stop",
            method: .post,
            body: StopBody(transactionPk: nil)
        )
        do {
            try await api.send(endpoint)
            // Optimistic flip → stopping; real session lands on refresh.
            if let existing = session {
                session = ChargerSession(
                    chargerId: existing.chargerId,
                    sessionId: existing.sessionId,
                    state: .stopping,
                    startedAt: existing.startedAt,
                    idTag: existing.idTag,
                    customerName: existing.customerName,
                    kwh: existing.kwh,
                    kw: existing.kw,
                    amps: existing.amps,
                    maxAmps: existing.maxAmps,
                    elapsedSec: existing.elapsedSec,
                    connectorId: existing.connectorId
                )
            }
            await loadSessionAndReservations()
        } catch let error as APIError {
            loadState = .error(message: messageForStartStop(error), raw: error)
        } catch {
            loadState = .error(message: "Couldn't stop charging. Try again.", raw: nil)
        }
    }

    /// Cancel a reservation row. Optimistically removes the row before
    /// the request; on failure the next `refresh()` will resurrect it
    /// from the wire.
    public func cancelReservation(_ id: String, confirmed: Bool) async {
        guard confirmed, !actionInFlight else { return }
        actionInFlight = true
        defer { actionInFlight = false }

        // Optimistic remove.
        let snapshot = reservations
        reservations.removeAll { $0.reservationId == id }

        let endpoint = Endpoint.with(
            path: "/api/admin/devices/\(entry.chargerId)/cancel-reservation",
            method: .delete,
            body: CancelBody(reservationId: id)
        )
        do {
            try await api.send(endpoint)
        } catch let error as APIError {
            // Rollback on hard failure (offline / 4xx).
            reservations = snapshot
            loadState = .error(message: messageForCancel(error), raw: error)
        } catch {
            reservations = snapshot
            loadState = .error(message: "Couldn't cancel reservation. Try again.", raw: nil)
        }
    }

    // MARK: - Private

    /// Lazily fetch the customer list before showing the picker. Cached
    /// for the lifetime of the VM — the operator typically picks once.
    private func ensureCustomersLoaded() async {
        if !customers.isEmpty { return }
        let endpoint = Endpoint(
            path: "/api/admin/devices/\(entry.chargerId)/customers",
            method: .get
        )
        do {
            let response: CustomersResponse = try await api.request(endpoint)
            customers = response.customers
        } catch {
            // Soft failure — picker still opens with an empty list and
            // the view renders an empty-state message.
            customers = []
        }
    }

    private func loadSessionAndReservations() async {
        async let sessionResult = loadSession()
        async let reservationsResult = loadReservations()
        let (session, reservations) = await (sessionResult, reservationsResult)

        // First-error wins; otherwise both succeeded.
        if let failure = [session.failure, reservations.failure].compactMap({ $0 }).first {
            loadState = .error(message: failure.message, raw: failure.raw)
            return
        }
        if let s = session.value { self.session = s }
        if let r = reservations.value { self.reservations = r }
        loadState = .ok
    }

    private struct PartialFailure: Sendable {
        let message: String
        let raw: APIError?
    }

    private struct PartialResult<T: Sendable>: Sendable {
        let value: T?
        let failure: PartialFailure?
    }

    private func loadSession() async -> PartialResult<ChargerSession?> {
        let endpoint = Endpoint(
            path: "/api/admin/devices/\(entry.chargerId)/session",
            method: .get
        )
        do {
            let response: ChargerSessionResponse = try await api.request(endpoint)
            return PartialResult(value: .some(response.session), failure: nil)
        } catch let error as APIError {
            return PartialResult(
                value: nil,
                failure: PartialFailure(message: messageForLoad(error), raw: error)
            )
        } catch {
            return PartialResult(
                value: nil,
                failure: PartialFailure(message: "Couldn't load session.", raw: nil)
            )
        }
    }

    private func loadReservations() async -> PartialResult<[Reservation]> {
        let endpoint = Endpoint(
            path: "/api/admin/devices/\(entry.chargerId)/reservations",
            method: .get
        )
        do {
            let response: ReservationsResponse = try await api.request(endpoint)
            return PartialResult(value: response.reservations, failure: nil)
        } catch let error as APIError {
            return PartialResult(
                value: nil,
                failure: PartialFailure(message: messageForLoad(error), raw: error)
            )
        } catch {
            return PartialResult(
                value: nil,
                failure: PartialFailure(message: "Couldn't load reservations.", raw: nil)
            )
        }
    }

    private func messageForLoad(_ error: APIError) -> String {
        error.customerFacingMessage(in: .chargerDetailLoad)
    }

    private func messageForStartStop(_ error: APIError) -> String {
        error.customerFacingMessage(in: .chargerCommand)
    }

    private func messageForCancel(_ error: APIError) -> String {
        error.customerFacingMessage(in: .reservationCancel)
    }

    // MARK: - Wire-body shapes

    private struct StartBody: Encodable, Sendable {
        let lagoCustomerExternalId: String
        let reservationId: String?
    }

    private struct StopBody: Encodable, Sendable {
        let transactionPk: Int?
    }

    private struct CancelBody: Encodable, Sendable {
        let reservationId: String
    }
}
