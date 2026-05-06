//
//  EventStreamReconnector.swift
//  ExpresScan
//
//  Wraps `EventStreamService` (in `Networking`) with reconnect logic.
//  Backoff schedule: 1 → 2 → 4 → 8 → 30 s, with ±25% jitter. The
//  most recent `id:` is preserved across reconnect attempts so the
//  server can resume the SSE stream from where the iOS client
//  dropped off.
//
//  Surfaces a single `AsyncThrowingStream<SSEEvent, Error>` to the
//  caller (`ScanCoordinator`). The stream auto-reconnects forever; only
//  `.unauthorized` / `.gone` failures bubble out as errors (so the
//  coordinator can clear keychain and route to welcome). Cancellation
//  finishes the stream cleanly.
//
//  Spec: `50-ios.md` § "SSE client"
//

import AuthCore
import Foundation
import Networking

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
public final class EventStreamReconnector {

    /// Backoff schedule. Elements in seconds. The last value is reused
    /// indefinitely (capped retry interval).
    public static let backoffSchedule: [TimeInterval] = [1, 2, 4, 8, 30]

    /// `±0.25` => up to 25% jitter on each delay.
    public static let jitterFraction: Double = 0.25

    private let environment: AppEnvironment
    /// Optional hook so the coordinator can render "Reconnecting…"
    /// pills + bump a counter for the diagnostics sheet.
    public var onReconnectScheduled: (@MainActor () -> Void)?

    /// Most recent observed `id:` field — sent on the next connect via
    /// `Last-Event-ID`.
    private var lastEventID: String?
    /// Current backoff index. Reset on every successful connect.
    private var attempt: Int = 0

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// Returns a self-reconnecting event stream. Iteration order:
    ///
    /// 1. Open SSE connection.
    /// 2. Yield events until the underlying stream finishes.
    /// 3. Schedule a backoff sleep, then loop back to step 1.
    /// 4. On `.unauthorized` / `.gone`, bubble the error and stop.
    public func events() -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream<SSEEvent, Error> { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                await self.runReconnectLoop(continuation: continuation)
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Loop

    private func runReconnectLoop(
        continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation
    ) async {
        let url = environment.api.baseURL.appendingPathComponent("/api/devices/scan-stream")

        while !Task.isCancelled {
            // Build a token-source closure scoped to this connect attempt.
            let tokenSource: @Sendable () async -> String? = { [environment] in
                (try? await environment.authStore.loadDeviceToken()) ?? nil
            }

            let service = EventStreamService(
                url: url,
                tokenSource: tokenSource,
                initialLastEventID: lastEventID
            )

            // `events()` is on an actor — `await` to obtain the stream
            // before iterating.
            let stream = await service.events()
            do {
                for try await event in stream {
                    if let id = event.id { lastEventID = id }
                    attempt = 0  // any successful event resets backoff
                    continuation.yield(event)
                }
                // Stream finished cleanly (server closed).
            } catch is CancellationError {
                continuation.finish()
                return
            } catch EventStreamError.unauthorized {
                continuation.finish(throwing: EventStreamError.unauthorized)
                return
            } catch EventStreamError.gone {
                continuation.finish(throwing: EventStreamError.gone)
                return
            } catch {
                // Network / transient server — fall through to backoff.
            }

            // Schedule a retry with backoff + jitter.
            let delay = nextDelay()
            attempt += 1
            onReconnectScheduled?()
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                continuation.finish()
                return
            }
        }
        continuation.finish()
    }

    // MARK: - Backoff math

    /// Compute the delay for the next reconnect attempt, applying the
    /// configured jitter.
    func nextDelay() -> TimeInterval {
        let schedule = Self.backoffSchedule
        let base = attempt < schedule.count ? schedule[attempt] : schedule.last ?? 30
        let jitterAmount = base * Self.jitterFraction
        // SystemRandomNumberGenerator is fine here — not a security
        // primitive, just spread out reconnects.
        let jitter = Double.random(in: -jitterAmount...jitterAmount)
        return max(0.1, base + jitter)
    }
}
