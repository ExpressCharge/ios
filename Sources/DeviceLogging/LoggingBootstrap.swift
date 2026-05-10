//
//  LoggingBootstrap.swift
//  DeviceLogging
//
//  Single entry point the app target calls during launch to wire the
//  swift-log `LoggingSystem` against our two backends. Idempotent —
//  calling more than once installs the new factory but doesn't crash.
//
//  Caller responsibility: provide the `device.id` (already in keychain
//  per AuthCore), the marketing version, and a `RingBufferLogStore`
//  instance. The store should outlive the process — typically owned
//  by `AppEnvironment`.
//

import Foundation
import Logging

public enum LoggingBootstrap {

    /// Installed handles for app-side reuse (drain hand-off, diagnostics
    /// sheet readout, token-revocation purge).
    public struct Handles: Sendable {
        public let store: RingBufferLogStore
        public let sequencer: LogSequencer

        public init(store: RingBufferLogStore, sequencer: LogSequencer) {
            self.store = store
            self.sequencer = sequencer
        }
    }

    /// Bootstrap the global logging system. Returns the handles the app
    /// keeps — drain hand-off and diagnostics need both the store
    /// (to read) and the sequencer (so post-restart allocations stay
    /// monotonic).
    ///
    /// - Parameter deviceId: from AuthCore keychain. Empty string is
    ///   tolerated for cold-launch-pre-registration; resource block
    ///   simply omits `device.id` until the next bootstrap pass.
    /// - Parameter serviceName: defaults to `"ExpresScan-iOS"`. Override
    ///   for kiosk variants if needed.
    /// - Parameter serviceVersion: marketing version, e.g. `"1.4.2"`.
    /// - Parameter osName: e.g. `"iOS"`.
    /// - Parameter osVersion: e.g. `"26.0"`.
    /// - Parameter logLevel: minimum level both backends emit.
    @discardableResult
    public static func bootstrap(
        deviceId: String,
        serviceName: String = "ExpresScan-iOS",
        serviceVersion: String,
        osName: String,
        osVersion: String,
        logLevel: Logger.Level = .info
    ) async throws -> Handles {
        let directory = try RingBufferLogStore.defaultLocation()
        let store = try await Self.makeStore(directory: directory)
        let sequencer = LogSequencer()

        // Reconcile: post-restart, sequencer should allocate strictly
        // above any seq already on disk OR already acked. Without this
        // a fresh `LogSequencer` could hand out 1, colliding with a
        // pre-existing record's seq 1 from a prior boot.
        let highest = await store.highestSeqOnDisk()
        let acked = await store.lastAckedSeq()
        let floor = max(highest, acked, sequencer.current)
        if floor > sequencer.current {
            sequencer.reset(to: floor)
        }

        let resource = ResourceProvider.build(
            serviceName: serviceName,
            serviceVersion: serviceVersion,
            deviceId: deviceId.isEmpty ? nil : deviceId,
            osName: osName,
            osVersion: osVersion
        )

        // Capture by reference for the factory. swift-log calls the
        // factory once per Logger label and caches the result, so the
        // closure runs rarely.
        LoggingSystem.bootstrap { label in
            let osHandler = OSLogHandler(label: label)
            var jsonHandler = RingBufferJSONLogHandler(
                label: label,
                store: store,
                sequencer: sequencer,
                resource: resource
            )
            jsonHandler.logLevel = logLevel
            var multiplex = MultiplexLogHandler([osHandler, jsonHandler])
            multiplex.logLevel = logLevel
            return multiplex
        }

        return Handles(store: store, sequencer: sequencer)
    }

    /// Actor-owning the disk handle is created off-actor so the bootstrap
    /// caller doesn't need an `await` chain at the call site beyond the
    /// initial `bootstrap`. Helper exists so unit tests can inject a
    /// store from a temp directory.
    private static func makeStore(directory: URL) async throws -> RingBufferLogStore {
        try RingBufferLogStore(directory: directory)
    }
}
