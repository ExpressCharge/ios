//
//  KeychainStore.swift
//  AuthCore
//
//  Thin wrapper over `SecItemCopyMatching` / `Add` / `Update` / `Delete`.
//  Domain logic (which item gets which accessibility) lives in `AuthStore`.
//
//  Spec: `60-security.md` § 2 ("Token storage on device").
//

import Foundation
import Security

/// Errors emitted by `KeychainStore`. Wraps the raw `OSStatus` so callers
/// can log / branch without importing Security symbols themselves.
public enum KeychainError: Error, Equatable, Sendable {
    case unhandled(status: OSStatus)
    /// `SecItemCopyMatching` returned a non-`Data` value (shouldn't happen
    /// for our usage, but defensively handled).
    case unexpectedItemFormat
}

/// Logical accessibility classes. The raw values map onto the
/// `kSecAttrAccessible*` constants when the item is added.
public enum KeychainAccessibility: Sendable, Equatable {
    /// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
    case whenUnlockedThisDeviceOnly
    /// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — required when
    /// the item must be readable while the app is in the background
    /// (e.g. the bearer token used by the heartbeat path).
    case afterFirstUnlockThisDeviceOnly

    fileprivate var cfValue: CFString {
        switch self {
        case .whenUnlockedThisDeviceOnly:
            return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .afterFirstUnlockThisDeviceOnly:
            return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
    }
}

/// A wrapper over the iOS keychain scoped to a single `service`.
public struct KeychainStore: Sendable {
    public let service: String

    /// Default service identifier. Production callers MUST use
    /// `KeychainStore.production` (or the convenience initialiser); the
    /// raw initialiser exists so tests can use a unique service id.
    public static let productionService = "express.polaris.ios"

    public init(service: String) {
        self.service = service
    }

    /// Production singleton convenience.
    public static let production = KeychainStore(service: productionService)

    // MARK: - CRUD

    /// Common keys we put on every query so iOS and macOS behave the
    /// same way:
    ///
    ///  - `kSecUseDataProtectionKeychain: true` opts macOS into the
    ///    iOS-style data-protection keychain. Without it, accessibility
    ///    classes are silently ignored, sync attributes diverge, and
    ///    `SecItemDelete` returns success after deleting only the first
    ///    match (which broke `deleteAll()` on a unit-test host).
    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecUseDataProtectionKeychain: true,
        ]
    }

    /// Reads the value stored for `account`, or `nil` if there is none.
    /// Throws on an unexpected `OSStatus`.
    public func get(account: String) throws -> Data? {
        var query = baseQuery
        query[kSecAttrAccount] = account
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        // `kSecUseAuthenticationContext` etc. are caller's concern;
        // we don't suppress the system biometric prompt here.

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.unexpectedItemFormat
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandled(status: status)
        }
    }

    /// Inserts or updates the value for `account`. The accessibility class
    /// + user-presence flag are applied on insert; on update they are
    /// preserved (Apple's recommendation — re-applying them via
    /// `SecItemUpdate` is unsupported).
    public func set(
        account: String,
        value: Data,
        accessibility: KeychainAccessibility,
        requiresUserPresence: Bool
    ) throws {
        // Build the access-control object if needed. `.userPresence`
        // requires a paired accessibility — we always use the supplied one.
        let access: SecAccessControl?
        if requiresUserPresence {
            var error: Unmanaged<CFError>?
            guard
                let ac = SecAccessControlCreateWithFlags(
                    nil,
                    accessibility.cfValue,
                    .userPresence,
                    &error
                )
            else {
                if let cfErr = error?.takeRetainedValue() {
                    let status = OSStatus(CFErrorGetCode(cfErr))
                    throw KeychainError.unhandled(status: status)
                }
                throw KeychainError.unhandled(status: errSecParam)
            }
            access = ac
        } else {
            access = nil
        }

        // Try insert first; on duplicate, update.
        var addQuery = baseQuery
        addQuery[kSecAttrAccount] = account
        addQuery[kSecValueData] = value
        addQuery[kSecAttrSynchronizable] = false
        if let access {
            addQuery[kSecAttrAccessControl] = access
        } else {
            addQuery[kSecAttrAccessible] = accessibility.cfValue
        }

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            // Update path: only `kSecValueData` is mutable here. The
            // accessibility / access-control attrs are sticky from the
            // original insert.
            var findQuery = baseQuery
            findQuery[kSecAttrAccount] = account
            let attrs: [CFString: Any] = [
                kSecValueData: value,
            ]
            let updateStatus = SecItemUpdate(
                findQuery as CFDictionary,
                attrs as CFDictionary
            )
            if updateStatus != errSecSuccess {
                throw KeychainError.unhandled(status: updateStatus)
            }
        default:
            throw KeychainError.unhandled(status: addStatus)
        }
    }

    /// Deletes the entry for `account`. Missing entries are not an error.
    public func delete(account: String) throws {
        var query = baseQuery
        query[kSecAttrAccount] = account
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainError.unhandled(status: status)
        }
    }

    /// Deletes every entry under this service. Used by `AuthStore.deleteAll()`.
    public func deleteAll() throws {
        // With `kSecUseDataProtectionKeychain: true` (folded into
        // `baseQuery`), this deletes every matching item in one call.
        // Without it, macOS's legacy keychain only deletes the first
        // match per call, leaving siblings behind.
        let status = SecItemDelete(baseQuery as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainError.unhandled(status: status)
        }
    }
}
