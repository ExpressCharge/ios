//
//  NFCService.swift
//  ExpresScan
//
//  Wraps `NFCTagReaderSession` in an async/await API. The session
//  delivers callbacks on its own dispatch queue; we bridge them via a
//  `CheckedContinuation` and marshal the resume back to `@MainActor` so
//  the caller (`ScanCoordinator`) stays on the main isolation boundary.
//
//  Polling options:
//    - `.iso14443` — covers MIFARE DESFire, MIFARE Ultralight, and the
//      generic NFC-A / NFC-B EV cards.
//    - `.iso15693` — long-range tags (less common in EV but cheap to
//      include).
//    - We deliberately do NOT poll for `.iso18092` (FeliCa) because the
//      Charge-Card vendors we support don't ship FeliCa; the branch is
//      kept in the switch below for forward compat.
//
//  MIFARE Classic detection: per `50-ios.md` § "NFC service", iPhone
//  CAN'T read MIFARE Classic. The CoreNFC SDK doesn't even expose a
//  `.classic` case on `NFCMiFareFamily` — the framework filters those
//  tags out at polling time, so they never reach our delegate.  If a
//  card slips through with an unknown family we surface the generic
//  unsupported-tag path.
//
//  Spec:
//    - `50-ios.md` § "NFC service"
//    - `50-ios.md` § "Card support matrix"
//

import CoreNFC
import Crypto
import Foundation

/// Errors emitted from `NFCService.scan(...)`.
public enum NFCError: Error, Equatable, Sendable {
    /// `NFCReaderError.readerSessionInvalidationErrorSessionTimeout`.
    case timeout
    /// `NFCReaderError.readerSessionInvalidationErrorUserCanceled` —
    /// surfaced as ".readyToScan" by the coordinator (no error UI).
    case userCanceled
    /// We saw a MIFARE Classic tag; we explicitly reject these.
    case mifareClassicUnsupported
    /// Tag was readable but its family is one we don't support.
    case unsupportedTag(family: String)
    /// `NFCReaderSession.isReady == false` — older device or simulator.
    case systemUnavailable
    /// Wrap any other `NFCReaderError` we don't translate explicitly.
    case underlying(code: Int, message: String)
}

/// Successful scan output: hex-uppercase identifier matching the
/// backend's `steveOcppIdTag` storage, plus a coarse tag-family label
/// for diagnostics.
public struct NFCScanResult: Sendable, Equatable {
    /// Hex-uppercase. Already shaped for the wire format.
    public let idTag: String
    /// `"miFare"`, `"iso7816"`, `"iso15693"`, `"feliCa"`. Free-text;
    /// just used for analytics + the diagnostics sheet.
    public let tagType: String

    public init(idTag: String, tagType: String) {
        self.idTag = idTag
        self.tagType = tagType
    }
}

/// Async/await wrapper around `NFCTagReaderSession`. Each `scan(...)`
/// call creates a fresh session — the `NFCTagReaderSession` API is
/// strictly one-shot.
public final class NFCService: NSObject, @unchecked Sendable {

    // The session and continuation are mutated only on the session's
    // delegate queue (the main queue, since we pass `nil`), so the
    // `@unchecked Sendable` is safe in practice.
    private var session: NFCTagReaderSession?
    private var continuation: CheckedContinuation<NFCScanResult, Error>?

    public override init() {
        super.init()
    }

    /// Begins an NFC tag-reader session and resolves with the first
    /// successfully-read tag's UID, or throws on timeout / cancel /
    /// unsupported card.
    ///
    /// - Parameters:
    ///   - timeoutSeconds: How long to wait before iOS auto-invalidates
    ///     the session with a timeout.
    ///   - alertMessage: User-visible text in the iOS-supplied scanner
    ///     sheet.
    public func scan(
        timeoutSeconds: Int,
        alertMessage: String
    ) async throws -> NFCScanResult {
        // Disallow reentry. A second concurrent caller waits.
        if continuation != nil {
            throw NFCError.systemUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            // The CoreNFC framework requires a delegate queue; passing
            // `nil` runs callbacks on the main queue, which keeps
            // `@MainActor` marshalling cheap.
            guard NFCTagReaderSession.readingAvailable else {
                continuation.resume(throwing: NFCError.systemUnavailable)
                return
            }

            let session = NFCTagReaderSession(
                pollingOption: [.iso14443, .iso15693],
                delegate: self,
                queue: nil
            )

            guard let session else {
                continuation.resume(throwing: NFCError.systemUnavailable)
                return
            }

            session.alertMessage = alertMessage
            self.session = session
            self.continuation = continuation

            session.begin()

            // iOS itself enforces session timeouts — but `timeoutSeconds`
            // gives us a safety net (e.g. on iOS 18 simulator-debug, the
            // delegate stays silent forever). We fire-and-forget a timer
            // that invalidates the session if no tag arrives.
            let captured = session
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                guard self?.session === captured else { return }
                self?.fail(with: NFCError.timeout, message: "No card detected. Try again.")
            }
        }
    }

    // MARK: - Internal

    /// Resolves the active continuation with a result and tears down
    /// the session.
    fileprivate func succeed(with result: NFCScanResult, message: String) {
        let cont = continuation
        continuation = nil
        session?.alertMessage = message
        session?.invalidate()
        session = nil
        cont?.resume(returning: result)
    }

    /// Resolves the active continuation with an error and invalidates
    /// the session with a user-facing error message.
    fileprivate func fail(with error: NFCError, message: String) {
        let cont = continuation
        continuation = nil
        session?.invalidate(errorMessage: message)
        session = nil
        cont?.resume(throwing: error)
    }

    /// Externally cancel the active session — used when the admin's
    /// `event: scan.cancelled` arrives while we're mid-NFC, so the iOS
    /// reader sheet dismisses without the user having to tap Cancel.
    /// Treated as a user-cancel (no error UI). Pinned to `@MainActor`
    /// because the underlying `session` / `continuation` storage is
    /// mutated only on the main queue (the delegate queue is `nil`
    /// → main).
    @MainActor
    public func cancel() {
        guard continuation != nil else { return }
        fail(with: .userCanceled, message: "Cancelled.")
    }
}

// MARK: - NFCTagReaderSessionDelegate

extension NFCService: NFCTagReaderSessionDelegate {

    public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // No-op. We don't need an analytics ping here.
    }

    public func tagReaderSession(
        _ session: NFCTagReaderSession,
        didInvalidateWithError error: Error
    ) {
        // The delegate queue is the main queue (we passed nil), so we
        // can hop to MainActor cheaply.
        Task { @MainActor [weak self] in
            guard let self else { return }
            // If the session resolved before iOS invalidated it
            // (success path), the continuation is already nil.
            guard self.continuation != nil else { return }

            let nfcError = Self.mapInvalidationError(error)
            // No `invalidate(errorMessage:)` — iOS already invalidated.
            let cont = self.continuation
            self.continuation = nil
            self.session = nil
            cont?.resume(throwing: nfcError)
        }
    }

    public func tagReaderSession(
        _ session: NFCTagReaderSession,
        didDetect tags: [NFCTag]
    ) {
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No card detected.")
            return
        }

        // Pre-extract everything we need from the tag synchronously
        // (the `identifier` / `mifareFamily` properties are valid pre-
        // connect). This keeps the `session.connect` completion
        // handler — which is `@Sendable` — from capturing the
        // non-Sendable `NFCTag`.
        let outcome = Self.extractOutcome(from: tag)

        // Connect to the tag, then deliver the pre-extracted outcome.
        session.connect(to: tag) { [weak self] connectError in
            guard let self else { return }
            if let connectError {
                let code = (connectError as NSError).code
                let message = connectError.localizedDescription
                Task { @MainActor in
                    self.fail(
                        with: .underlying(code: code, message: message),
                        message: "Couldn't read that card. Try again."
                    )
                }
                return
            }

            switch outcome {
            case .success(let result):
                Task { @MainActor in
                    self.succeed(with: result, message: "Card read.")
                }
            case .mifareClassic:
                Task { @MainActor in
                    self.fail(
                        with: .mifareClassicUnsupported,
                        message: "This card isn't supported. Try a different one."
                    )
                }
            case .unsupported(let family):
                Task { @MainActor in
                    self.fail(
                        with: .unsupportedTag(family: family),
                        message: "This card isn't supported. Try a different one."
                    )
                }
            }
        }
    }

    /// Sendable summary of a detected tag. Computed eagerly so the
    /// `@Sendable` connect-completion closure never captures the
    /// underlying `NFCTag`.
    private enum TagOutcome: Sendable {
        case success(NFCScanResult)
        case mifareClassic
        case unsupported(family: String)
    }

    private static func extractOutcome(from tag: NFCTag) -> TagOutcome {
        switch tag {
        case .miFare(let mifare):
            // CoreNFC has no `.classic` case (iPhones can't read
            // MIFARE Classic at all); `.unknown` is the closest we
            // ever see for an oddball Type-A tag we shouldn't trust
            // the UID of, so we reject those defensively.
            if mifare.mifareFamily == .unknown {
                return .mifareClassic
            }
            let uid = mifare.identifier.hexUppercased
            let family = mifareFamilyLabel(mifare.mifareFamily)
            return .success(NFCScanResult(idTag: uid, tagType: family))

        case .iso7816(let iso):
            let uid = iso.identifier.hexUppercased
            return .success(NFCScanResult(idTag: uid, tagType: "iso7816"))

        case .iso15693(let iso):
            let uid = iso.identifier.hexUppercased
            return .success(NFCScanResult(idTag: uid, tagType: "iso15693"))

        case .feliCa(let felica):
            // FeliCa lacks an `identifier` — the IDm is the closest
            // analogue.
            let idm = felica.currentIDm.hexUppercased
            return .success(NFCScanResult(idTag: idm, tagType: "feliCa"))

        @unknown default:
            return .unsupported(family: "unknown")
        }
    }

    // MARK: - Helpers

    private static func mapInvalidationError(_ error: Error) -> NFCError {
        let nsError = error as NSError
        // The CoreNFC errors are documented under `NFCReaderError`;
        // its raw codes live in `NFCReaderError.Code`.
        if let readerCode = NFCReaderError.Code(rawValue: nsError.code) {
            switch readerCode {
            case .readerSessionInvalidationErrorSessionTimeout:
                return .timeout
            case .readerSessionInvalidationErrorUserCanceled:
                return .userCanceled
            case .readerSessionInvalidationErrorSystemIsBusy,
                .readerSessionInvalidationErrorFirstNDEFTagRead,
                .readerSessionInvalidationErrorSessionTerminatedUnexpectedly:
                return .underlying(code: nsError.code, message: nsError.localizedDescription)
            default:
                return .underlying(code: nsError.code, message: nsError.localizedDescription)
            }
        }
        return .underlying(code: nsError.code, message: nsError.localizedDescription)
    }

    private static func mifareFamilyLabel(_ family: NFCMiFareFamily) -> String {
        switch family {
        case .ultralight: return "miFare-ultralight"
        case .plus: return "miFare-plus"
        case .desfire: return "miFare-desfire"
        case .unknown: return "miFare-unknown"
        @unknown default: return "miFare-unknown"
        }
    }
}
