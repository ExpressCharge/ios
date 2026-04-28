//
//  DeviceStateService.swift
//  DeviceSync
//
//  Calls the `GET /api/devices/me/state` and `POST /api/devices/me/state/sync`
//  endpoints via `APIClient` and decodes the `DeviceState` envelope.
//
//  Bearer auth is required for both endpoints; `APIClient` handles
//  attaching the token via its `tokenSource`.
//

import Foundation
import Models
import Networking
import AuthCore

public struct DeviceStateService: Sendable {

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    /// `GET /api/devices/me/state` — full envelope.
    public func fetchState() async throws -> DeviceState {
        let endpoint = Endpoint(
            path: "/api/devices/me/state",
            method: .get,
            requiresAuth: true
        )
        return try await api.request(endpoint)
    }

    /// `POST /api/devices/me/state/sync` — submit pending settings +
    /// diagnostics, get the merged envelope back.
    public func sync(_ body: SyncRequest) async throws -> DeviceState {
        let endpoint = Endpoint.with(
            path: "/api/devices/me/state/sync",
            method: .post,
            requiresAuth: true,
            body: body
        )
        return try await api.request(endpoint)
    }
}
