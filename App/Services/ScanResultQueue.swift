//
//  ScanResultQueue.swift
//  ExpresScan
//
//  Persists `ScanResultRequest` bodies that fail the initial POST due
//  to network errors. On app foreground / SSE reconnect, the
//  coordinator drains the queue with exponential backoff, posting each
//  body in arrival order.
//
//  Storage: JSON files under
//  `FileManager.default.url(for: .applicationSupportDirectory)/ScanResultQueue/`.
//  One file per item, named `<timestamp>-<uuid>.json`. The arrival
//  ordering is the file-creation timestamp.
//
//  We deliberately don't use UserDefaults — the items contain a HMAC
//  nonce + a 14-character idTag; UserDefaults is plist-encoded and
//  shows up in iCloud backup / encrypted backups, which is fine, but
//  the file path is more explicit and easier to inspect during QA.
//
//  Spec: `50-ios.md` § "Offline scan queue"
//

import Foundation
import Models
import Networking

public actor ScanResultQueue {

    private let api: APIClient
    private let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    /// Per-item retry backoff schedule. We move on to the next item if
    /// a single item fails repeatedly.
    private let retrySchedule: [TimeInterval]

    public init(
        api: APIClient,
        fileManager: FileManager = .default,
        directoryName: String = "ScanResultQueue",
        retrySchedule: [TimeInterval] = [0, 1, 4]
    ) {
        self.api = api
        self.fileManager = fileManager
        let base: URL
        if let appSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            base = appSupport
        } else {
            base = fileManager.temporaryDirectory
        }
        self.directory = base.appendingPathComponent(directoryName, isDirectory: true)
        try? fileManager.createDirectory(
            at: self.directory,
            withIntermediateDirectories: true
        )
        self.retrySchedule = retrySchedule
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    /// Persist a `ScanResultRequest` for later retry.
    public func enqueue(body: ScanResultRequest) {
        let id = UUID().uuidString
        let stamp = Int64(Date().timeIntervalSince1970 * 1000)
        let url = directory.appendingPathComponent("\(stamp)-\(id).json")
        do {
            let data = try encoder.encode(body)
            try data.write(to: url, options: .atomic)
        } catch {
            // Disk write failed — the user's offline scan is lost.
            // Surfacing this on screen would be alarming; the diagnostics
            // sheet picks it up via the queue count instead.
            scanLog.error(
                "Failed to enqueue offline scan result: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Snapshot count of pending items. Cheap enough to call from the
    /// home screen.
    public func count() -> Int {
        (try? listSorted().count) ?? 0
    }

    /// Drain the queue, posting each item in order. Returns the number
    /// of items still pending after the drain attempt. The optional
    /// `onProgress` closure is invoked with the count after each
    /// successful drain step so the UI can update its badge.
    @discardableResult
    public func drain(onProgress: @escaping @Sendable (Int) -> Void = { _ in }) async -> Int {
        let items: [URL]
        do {
            items = try listSorted()
        } catch {
            return 0
        }

        for item in items {
            // Short retry per item — the global app-foreground will
            // re-call drain() as needed.
            var sent = false
            for delay in retrySchedule {
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
                if await postItem(at: item) {
                    sent = true
                    onProgress(currentCount())
                    break
                }
            }
            if !sent {
                // Stop on the first persistently-failing item — we
                // preserve order. Foreground will retry.
                break
            }
        }
        return currentCount()
    }

    // MARK: - Internals

    private func currentCount() -> Int {
        (try? listSorted().count) ?? 0
    }

    private func listSorted() throws -> [URL] {
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return
            urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Post one item; returns `true` on success (then the file is
    /// removed). Returns `false` on a network error (file kept). On a
    /// non-network failure (e.g. 410 / 401) the file is removed —
    /// retrying it would never succeed.
    private func postItem(at url: URL) async -> Bool {
        let body: ScanResultRequest
        do {
            let data = try Data(contentsOf: url)
            body = try decoder.decode(ScanResultRequest.self, from: data)
        } catch {
            try? fileManager.removeItem(at: url)
            return true
        }

        let endpoint = Endpoint.with(
            path: "/api/devices/scan-result",
            method: .post,
            requiresAuth: true,
            body: body
        )

        do {
            try await api.send(endpoint)
            try? fileManager.removeItem(at: url)
            return true
        } catch APIError.network {
            return false
        } catch {
            // Permanent failure. Drop the item so we don't loop.
            try? fileManager.removeItem(at: url)
            return true
        }
    }
}
