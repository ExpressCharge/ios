//
//  HeartbeatService.swift
//  ExpresScan
//
//  60-second `POST /api/devices/heartbeat` keep-alive. Runs while the
//  app is foregrounded; cancelled on backgrounding (per the HIG audit
//  recommendation in `50-ios.md` § "Heartbeat", we do NOT use
//  `BGAppRefreshTask` because Apple's discretionary scheduling means
//  it can't deliver the timeliness guarantees we need).
//
//  Implementation note: the spec asks for an `actor`, but Swift 6's
//  global-actor isolation rules make `@MainActor`-isolated `actor`
//  declarations awkward (the inner generic on `Task` falls through the
//  Sendable cracks). We use a plain `actor` (no `@MainActor`) and let
//  the public callers — which all live on `ScanCoordinator` — marshal
//  the start/stop calls themselves.
//
//  Spec: `50-ios.md` § "Heartbeat"
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(UIKit)
import UIKit
#endif

import Models
import Networking

/// 60-second heartbeat poster. Lives for the lifetime of a foreground
/// session.
public actor HeartbeatService {

    /// Period between heartbeats. Public for tests.
    public static let interval: TimeInterval = 60

    private let api: APIClient
    private var loop: Task<Void, Never>?

    public init(api: APIClient) {
        self.api = api
    }

    /// Begin (or restart) the heartbeat loop. Idempotent — calling it
    /// while the loop is already running is a no-op. The
    /// `deviceTokenAvailable` closure short-circuits the loop when the
    /// device is unregistered (the API call would 401).
    public func start(
        deviceTokenAvailable: @escaping @Sendable () async -> Bool,
        onSuccess: @escaping @Sendable () -> Void = {}
    ) {
        if loop != nil { return }
        loop = Task { [api] in
            while !Task.isCancelled {
                if await deviceTokenAvailable() {
                    let payload = HeartbeatPayload(
                        appVersion: Self.shortVersion,
                        osVersion: Self.osVersion
                    )
                    let endpoint = Endpoint.with(
                        path: "/api/devices/heartbeat",
                        method: .post,
                        requiresAuth: true,
                        body: payload
                    )
                    do {
                        try await api.send(endpoint)
                        onSuccess()
                    } catch {
                        // Swallow — the next tick retries. The
                        // reconnector's exponential backoff lives in
                        // EventStreamReconnector; the heartbeat path
                        // is "fire-and-forget" by design.
                    }
                }
                try? await Task.sleep(for: .seconds(Self.interval))
            }
        }
    }

    /// Cancel the loop. Safe to call multiple times.
    public func stop() {
        loop?.cancel()
        loop = nil
    }

    // MARK: - Static helpers

    private static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private static var osVersion: String {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }
}
