//
//  SettingsReconciler.swift
//  DeviceSync
//
//  Pure-logic last-write-wins merge for the per-key device-settings map.
//  Mirrors the backend's `mergeSettings(local, remote)` function so an
//  optimistic client can render the post-sync state before the server
//  responds, and so we can unit-test the LWW invariants in isolation.
//
//  Rules:
//   - For each key present in either map, pick the side with the *later*
//     `updatedAt`.
//   - On a tie (`==` timestamp), the *remote* (server) value wins. This
//     mirrors the backend, which is authoritative on equal-stamp races.
//   - Keys present only on one side pass through unchanged.
//

import Foundation

public enum SettingsReconciler {

    /// Merge two settings maps. The `local` map is the on-device pending
    /// state; `remote` is the server's authoritative snapshot. Returns
    /// the merged map.
    public static func merge(
        local: [String: DeviceSettingValue],
        remote: [String: DeviceSettingValue]
    ) -> [String: DeviceSettingValue] {
        var out = remote
        for (key, localValue) in local {
            if let remoteValue = out[key] {
                if localValue.updatedAt > remoteValue.updatedAt {
                    out[key] = localValue
                }
                // tie or older → keep remote (already there)
            } else {
                out[key] = localValue
            }
        }
        return out
    }
}
