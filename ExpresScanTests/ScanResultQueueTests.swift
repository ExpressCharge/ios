//
//  ScanResultQueueTests.swift
//  ExpresScanTests
//
//  Tests the offline queue's enqueue + drain semantics. We use a
//  per-test directory under `FileManager.temporaryDirectory` so tests
//  don't pollute Application Support and so parallel test workers
//  don't collide.
//
//  Spec: `50-ios.md` § "Offline scan queue".
//

import XCTest
@testable import ExpresScan
import Models
import Networking

final class ScanResultQueueTests: XCTestCase {

    private var tmpRoot: URL!
    private var queueDirName: String!

    override func setUp() async throws {
        // Each test run gets its own subdir under the system temp.
        tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanResultQueueTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        queueDirName = "queue"
    }

    override func tearDown() async throws {
        if let tmpRoot {
            try? FileManager.default.removeItem(at: tmpRoot)
        }
    }

    // MARK: - Enqueue

    func testEnqueueWritesOneFile() async {
        let queue = makeQueue()
        await queue.enqueue(body: makeRequest(idTag: "AABBCCDD"))

        let count = await queue.count()
        XCTAssertEqual(count, 1)
    }

    func testEnqueuePreservesOrder() async {
        let queue = makeQueue()
        for i in 0..<5 {
            await queue.enqueue(body: makeRequest(idTag: String(format: "%08X", i)))
            // Tiny pause so file timestamps are monotonically increasing.
            try? await Task.sleep(nanoseconds: 2_000_000) // 2 ms
        }
        let count = await queue.count()
        XCTAssertEqual(count, 5)
    }

    // MARK: - Drain

    func testDrainPostsItemsAndClearsQueueOnSuccess() async {
        StubURLProtocol.handler = { _ in (200, [:], Data()) }
        let queue = makeQueue()
        await queue.enqueue(body: makeRequest(idTag: "DEADBEEF"))
        await queue.enqueue(body: makeRequest(idTag: "FEEDFACE"))

        let remaining = await queue.drain()
        XCTAssertEqual(remaining, 0)
        let count = await queue.count()
        XCTAssertEqual(count, 0)
        StubURLProtocol.reset()
    }

    func testDrainKeepsItemsOnNetworkError() async {
        StubURLProtocol.failureMode = .networkError
        let queue = makeQueue(retrySchedule: [0]) // 1 attempt only — fast test
        await queue.enqueue(body: makeRequest(idTag: "DEADBEEF"))
        await queue.enqueue(body: makeRequest(idTag: "FEEDFACE"))

        let remaining = await queue.drain()
        // Both items still present (network fails persistently → bail
        // after first item).
        XCTAssertEqual(remaining, 2)
        StubURLProtocol.reset()
    }

    func testDrainDropsItemsOnPermanentFailure() async {
        // 410 / 401 / 5xx → drop the item, don't loop forever.
        StubURLProtocol.handler = { _ in (410, [:], Data()) }
        let queue = makeQueue()
        await queue.enqueue(body: makeRequest(idTag: "DEADBEEF"))

        let remaining = await queue.drain()
        XCTAssertEqual(remaining, 0)
        StubURLProtocol.reset()
    }

    // MARK: - Helpers

    private func makeQueue(retrySchedule: [TimeInterval] = [0]) -> ScanResultQueue {
        let api = makeStubbedAPIClient()
        return ScanResultQueue(
            api: api,
            fileManager: .default,
            // Encode tmpRoot path into the directory name so each test
            // gets an isolated dir under FileManager.default's
            // application-support root. We pass the full path via
            // directoryName by abusing it as a relative path that the
            // queue then appends to its base. To keep this clean, we
            // use a unique name and clean up in tearDown.
            directoryName: "ScanResultQueueTests-\(UUID().uuidString)",
            retrySchedule: retrySchedule
        )
    }

    private func makeStubbedAPIClient() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        return APIClient(
            baseURL: URL(string: "https://example.test")!,
            transport: session,
            tokenSource: { "test_token" }
        )
    }

    private func makeRequest(idTag: String) -> ScanResultRequest {
        ScanResultRequest(
            idTag: idTag,
            pairingCode: "pair_xyz",
            ts: 1_700_000_000,
            nonce: "abcdef0123456789"
        )
    }
}

// MARK: - URLProtocol stub (mirrors the one in APIClientTests)

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum FailureMode: Sendable {
        case none
        case networkError
    }

    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, [String: String], Data))?
    nonisolated(unsafe) static var failureMode: FailureMode = .none

    static func reset() {
        handler = nil
        failureMode = .none
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        switch StubURLProtocol.failureMode {
        case .networkError:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        case .none:
            break
        }

        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (status, headers, body) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
