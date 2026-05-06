//
//  RegistrationViewModel.swift
//  ExpresScan
//
//  POSTs `/api/devices/register` with the one-time `code`, the
//  matching PKCE `codeVerifier`, the user-chosen device label, and a
//  bag of device metadata. On success: stash the issued credentials in
//  the keychain, request APNs registration, and tell the
//  RootCoordinator to advance to notification priming.
//
//  Spec:
//    - `20-contracts.md` § "Endpoint detail: POST /api/devices/register".
//    - `60-security.md` § 1 (Universal Links + PKCE).
//
//  E-app-wire wires the actual `apnsToken` capture; right now we wait
//  briefly for an APNs token (best-effort) and otherwise send an empty
//  string — the backend tolerates it and `PUT /api/devices/{id}/push-token`
//  fills it in later.
//

import AuthCore
import Capabilities
import Foundation
import Models
import Networking
import Observation
import UIKit

@MainActor
@Observable
public final class RegistrationViewModel {

    /// User-editable label, defaults to `UIDevice.current.name`.
    public var label: String

    /// Multi-select capability set bound to `CapabilityPickerSection`.
    /// Defaults to `{.scanner, .user}` per the UX research P1-2
    /// recommendation (the most common admin combo).
    public var selectedCapabilities: Set<DeviceCapability>

    /// Set while the network call is in flight.
    public private(set) var isSubmitting: Bool = false
    /// Last error to display, cleared on each `submit()`.
    public private(set) var error: RegistrationError?
    /// Set true exactly once on success — RegistrationView observes
    /// this and triggers the coordinator transition.
    public private(set) var didSucceed: Bool = false

    /// One-time code from the Universal Link. Constant for the
    /// lifetime of this VM.
    public let oneTimeCode: String
    /// PKCE verifier matching the `codeChallenge` we sent.
    public let codeVerifier: String

    private let environment: AppEnvironment

    public init(
        environment: AppEnvironment,
        oneTimeCode: String,
        codeVerifier: String,
        defaultLabel: String? = nil,
        deviceName: String = UIDevice.current.name,
        localizedModel: String = UIDevice.current.localizedModel,
        deviceIdProvider: () -> String = { UIDevice.current.identifierForVendor?.uuidString ?? "" }
    ) {
        self.environment = environment
        self.oneTimeCode = oneTimeCode
        self.codeVerifier = codeVerifier
        self.selectedCapabilities = [.scanner, .user]

        if let provided = defaultLabel, !provided.trimmingCharacters(in: .whitespaces).isEmpty {
            self.label = provided
        } else {
            self.label = Self.resolveDefaultLabel(
                deviceName: deviceName,
                localizedModel: localizedModel,
                deviceIdLast4: Self.last4(of: deviceIdProvider())
            )
        }
    }

    /// Resolves the pre-fill label. When iOS returns the generic
    /// `"iPhone"` / `"iPad"` (entitlement not yet granted), falls back
    /// to `"<localizedModel> (<deviceId-last-4>)"` so labels are unique
    /// and don't impersonate the user. UX research P2-2.
    static func resolveDefaultLabel(
        deviceName: String,
        localizedModel: String,
        deviceIdLast4: String
    ) -> String {
        let trimmed = deviceName.trimmingCharacters(in: .whitespaces)
        let isGeneric =
            trimmed.isEmpty
            || trimmed.caseInsensitiveCompare("iPhone") == .orderedSame
            || trimmed.caseInsensitiveCompare("iPad") == .orderedSame
        if isGeneric {
            if deviceIdLast4.isEmpty {
                return localizedModel
            }
            return "\(localizedModel) (\(deviceIdLast4))"
        }
        return trimmed
    }

    private static func last4(of identifier: String) -> String {
        let stripped = identifier.replacingOccurrences(of: "-", with: "")
        guard stripped.count >= 4 else { return stripped }
        return String(stripped.suffix(4))
    }

    // MARK: - Submit

    public func submit() async {
        guard !isSubmitting else {
            authLog.debug("RegistrationViewModel.submit: ignored, already in flight")
            return
        }
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }

        // Reject illegal capability sets before going to the wire — the
        // server enforces the same rule, but we surface the failure
        // inline without a round-trip.
        guard !selectedCapabilities.isEmpty,
            DeviceCapability.isLegalSet(selectedCapabilities)
        else {
            let capList = self.selectedCapabilities.map(\.rawValue).joined(separator: ",")
            authLog.error(
                "RegistrationViewModel.submit: illegal capability set \(capList, privacy: .public)")
            self.error = .invalidCapabilities
            return
        }

        // Block briefly waiting for the APNs token if it hasn't
        // arrived yet — the priming flow asks for permission ahead of
        // submit() in the canonical user path, so the token is usually
        // already in `pendingApnsToken`. The bounded wait keeps the
        // submit responsive on declined-permission paths.
        let pushToken = await waitForApnsToken(timeout: 5.0) ?? ""
        authLog.debug(
            "RegistrationViewModel.submit: posting /api/devices/register, label.len=\(self.label.count, privacy: .public), pushToken.empty=\(pushToken.isEmpty, privacy: .public)"
        )

        let request = DeviceRegistrationRequest(
            oneTimeCode: oneTimeCode,
            codeVerifier: codeVerifier,
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            platform: "ios",
            model: deviceModelIdentifier(),
            osVersion: UIDevice.current.systemVersion,
            appVersion: Self.shortVersion,
            pushToken: pushToken,
            apnsEnvironment: BuildConfig.apnsEnvironment == "production" ? .production : .sandbox,
            requestedCapabilities: Array(selectedCapabilities).sorted { $0.rawValue < $1.rawValue }
        )

        let endpoint = Endpoint.with(
            path: "/api/devices/register",
            method: .post,
            requiresAuth: false,
            body: request
        )

        do {
            let response: DeviceRegistrationResponse = try await environment.api.request(endpoint)
            authLog.debug(
                "RegistrationViewModel.submit: registration succeeded, deviceId=\(response.deviceId, privacy: .public)"
            )

            // Persist the three secrets. `storeCredentials` applies
            // the per-item Keychain accessibility classes from
            // `60-security.md` § 2.
            try await environment.authStore.storeCredentials(
                deviceId: response.deviceId,
                deviceToken: response.deviceToken,
                deviceSecret: response.deviceSecret
            )

            // Trigger APNs registration so we have a token to upload
            // via PUT /push-token in the priming step.
            UIApplication.shared.registerForRemoteNotifications()

            didSucceed = true
        } catch let api as APIError {
            authLog.error(
                "RegistrationViewModel.submit: API error \(String(describing: api), privacy: .public)"
            )
            error = mapAPIError(api)
        } catch let kc as KeychainError {
            authLog.error(
                "RegistrationViewModel.submit: keychain error \(String(describing: kc), privacy: .public)"
            )
            self.error = .keychain
        } catch {
            authLog.error(
                "RegistrationViewModel.submit: unexpected error \(String(describing: error), privacy: .public)"
            )
            self.error = .other
        }
    }

    // MARK: - APNs token observation

    private var pendingApnsToken: String?
    private var apnsObserver: NSObjectProtocol?

    /// Begins listening for an APNs token; mostly useful when the user
    /// granted permission BEFORE clicking Register. The skeleton just
    /// captures the value; E-app-wire decides what to do with it.
    public func startObservingApnsToken() {
        apnsObserver = NotificationCenter.default.addObserver(
            forName: AppNotifications.apnsTokenReceived,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let token = note.userInfo?["token"] as? String
            Task { @MainActor in
                self?.pendingApnsToken = token
            }
        }
    }

    public func stopObservingApnsToken() {
        if let apnsObserver {
            NotificationCenter.default.removeObserver(apnsObserver)
            self.apnsObserver = nil
        }
    }

    /// Triggers an `application.registerForRemoteNotifications()` so the
    /// AppDelegate can deliver a token shortly. Idempotent.
    public func startWaitingForApnsToken() {
        // Prompt the system to deliver a token. Calling this when
        // notifications haven't been authorized yet is a no-op (no
        // token will be delivered) — that's fine; we then send an
        // empty `pushToken` and follow up with PUT /push-token after
        // priming.
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Polls `pendingApnsToken` for up to `timeout` seconds, returning
    /// the token if it arrives in time. Polling interval is 100 ms,
    /// which is cheap and keeps the dependency profile low (no
    /// per-call AsyncSequence machinery).
    private func waitForApnsToken(timeout: TimeInterval) async -> String? {
        if let token = pendingApnsToken, !token.isEmpty {
            return token
        }
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if let token = pendingApnsToken, !token.isEmpty {
                return token
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return pendingApnsToken
    }

    // MARK: - Helpers

    private static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Hardware identifier (e.g. `"iPhone16,2"`). UIDevice.model is
    /// the marketing name; we want the model identifier for the
    /// admin device list. Falls back to `model` when the syscall is
    /// unavailable (e.g. catalyst / preview).
    private func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { acc, element in
            if let value = element.value as? Int8, value != 0 {
                acc.append(Character(UnicodeScalar(UInt8(value))))
            }
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }

    private func mapAPIError(_ api: APIError) -> RegistrationError {
        switch api {
        case .gone: return .codeExpired
        case .unauthorized: return .unauthorized
        case .rateLimited: return .rateLimited
        case .network: return .network
        case .server(_, let code): return .server(code: code)
        default: return .other
        }
    }
}

public enum RegistrationError: Error, Equatable, Sendable {
    case codeExpired
    case unauthorized
    case rateLimited
    case network
    case keychain
    case server(code: String?)
    /// Selected capability set fails `DeviceCapability.isLegalSet` (e.g.
    /// kiosk + 2 base capabilities) or is empty.
    case invalidCapabilities
    case other
}
