# iOS App Implementation Plan (`expresscan`)

All work is in this repo. Tech: SwiftUI, iOS 17, Swift 6 (targeted strict
concurrency), Xcode 16+, no third-party dependencies.

## Project setup

- **Bundle ID:** `gg.vlad.expresscan`.
- **Apple Developer Team ID:** `48H7CLBV8Y` (paid account; required for NFC capability + push).
- **Full App ID:** `48H7CLBV8Y.gg.vlad.expresscan` (used in `apple-app-site-association` `appIDs`).
- **Deployment target:** iOS 17.0.
- **Swift language version:** 6 (with `StrictConcurrency = targeted`, not `complete`).
- **Capabilities:** Near Field Communication Tag Reading, Push Notifications, Associated Domains (for Universal Links).
- **Entitlements:**
  - `com.apple.developer.nfc.readersession.formats = ["TAG"]`
  - `com.apple.developer.associated-domains = ["applinks:manage.polaris.express"]`
  - `aps-environment` = `development` (Debug) / `production` (Release)
- **Info.plist:**
  - `NFCReaderUsageDescription`: "ExpresScan reads the unique ID from your NFC charge card so the charging station can verify your account and start your session."
  - `UIBackgroundModes` = `["remote-notification"]` (push only — no `fetch`, no `processing`)
- **Privacy manifest** (`PrivacyInfo.xcprivacy`): declare required-reasons-API entries for `UserDefaults` (`CA92.1`), `FileTimestamp` (`C617.1`) if accessed.

## Project structure

```
ExpresScan.xcodeproj
ExpresScan/
  App/
    ExpreScanApp.swift                  @main
    AppDelegate.swift                   UIApplicationDelegate (APNs)
    SceneDelegate.swift                 Universal Link routing
    AppEnvironment.swift                injected via .environment(\.app, ...)
    RootView.swift                      auth-gate
  Features/
    Welcome/
      WelcomeView.swift
    Auth/
      LoginViewModel.swift              ASWebAuthenticationSession orchestrator
    Registration/
      RegistrationView.swift
      RegistrationViewModel.swift       PKCE, /devices/register
    NotificationPriming/
      NotificationPrimingView.swift
    Scan/
      ReadyView.swift                   home screen
      ScanActiveView.swift              "scan a card now" + countdown
      SuccessView.swift
      ErrorView.swift
      ScanCoordinator.swift             @Observable; routes between states
      ScanState.swift                   enum
    Settings/
      SettingsView.swift
      DiagnosticsSheet.swift
  Services/
    APIClient.swift
    NFCService.swift
    PushService.swift
    EventStreamService.swift            SSE client
    HeartbeatService.swift
    AuthStore.swift                     reads/writes Keychain
    KeychainStore.swift
    ScanResultSigner.swift              CryptoKit HMAC
    ScanResultQueue.swift               offline queue persisted to disk
  Design/
    Theme.swift
    ColorTokens.swift                   wraps Color("PrimaryCyan") etc.
    Components/
      StatusPill.swift                  SF Symbol + text (NOT color-only)
      SubscriptionBadge.swift
      CountdownRing.swift
      AnimatedNFCGlyph.swift
  Models/
    DeviceRegistration.swift
    ScanRequest.swift                   matches DeviceScanRequestedPayload
    ScanResult.swift                    matches EnrichedScanResult
    HeartbeatPayload.swift
  Resources/
    Assets.xcassets                     colors with light/dark variants
    Localizable.strings                 (en only, structured for future i18n)
    PrivacyInfo.xcprivacy
ExpresScanTests/
  APIClientTests.swift
  ScanResultSignerTests.swift
  EventStreamServiceTests.swift
  ScanCoordinatorTests.swift
  HexEncodingTests.swift
ExpresScanUITests/
  OnboardingFlowTests.swift             non-NFC screens only
  SettingsScreenTests.swift
```

## State machine

```
enum ScanState {
  case idle
  case connecting                      // SSE opening
  case readyToScan                     // SSE open, no active request
  case scanRequested(ScanRequest)      // arm event arrived
  case scanning(ScanRequest)           // NFC session active
  case success(EnrichedScanResult)
  case error(ScanError)
  case offline                         // SSE down + push not seen
}
```

Transitions are driven by:
- `EventStreamService` emits `AsyncStream<StreamEvent>` (connected, scanRequested, sessionReplaced, tokenRevoked).
- `PushService` emits `pendingScanRequest` when a notification is tapped.
- `NFCService.scan(...)` returns `Result<UID, NFCError>`.
- `APIClient.postScanResult(...)` returns `Result<EnrichedScanResult, APIError>`.

The `ScanCoordinator` (single `@Observable @MainActor` class) holds the state
and routes inputs. Coalescing via `processedPairingCodes: [String: Date]`
(in-memory + UserDefaults mirror).

## Idempotency on writes

For every POST/PUT/DELETE call, `APIClient` generates a per-request UUID and
sends it in the `Idempotency-Key` header. The backend wraps these handlers in
`withIdempotency()` and caches the response for 24h, so a retry-after-
network-blip never produces a duplicate registration / double arm. See
`20-contracts.md` § "Idempotency-Key support" for the route list.

## Key implementation details

### NFC

```swift
let session = NFCTagReaderSession(
  pollingOption: [.iso14443, .iso15693],   // include 15693 per Apple HIG audit
  delegate: self,
  queue: nil
)
session.alertMessage = "Hold a card to the top of your iPhone."
session.begin()
```

In `tagReaderSession(_:didDetect:)`, dispatch by tag type:
- `.miFare(let mt)` → check `mt.mifareFamily`. `.classic` → invalidate with friendly message + throw `.mifareClassicUnsupported`. Otherwise read `.identifier`.
- `.iso7816(let t)` → read `.identifier`.
- `.iso15693(let t)` → read `.identifier`.
- `.feliCa(let t)` → read `.currentIDm`.

Encode UID: `bytes.map { String(format: "%02X", $0) }.joined()` — hex uppercase,
matches backend `steveOcppIdTag` storage exactly.

### HMAC for scan-result

```swift
import CryptoKit

struct ScanResultSigner {
  let secret: SymmetricKey  // base64url-decoded deviceSecret

  func sign(idTag: String, pairingCode: String, deviceId: String, ts: Int) -> String {
    let msg = "scan-result/v1|\(idTag)|\(pairingCode)|\(deviceId)|\(ts)"
    let mac = HMAC<SHA256>.authenticationCode(for: Data(msg.utf8), using: secret)
    return Data(mac).map { String(format: "%02x", $0) }.joined()
  }
}
```

The `"scan-result/v1|"` prefix is required for domain separation.

### Keychain storage

| Item | Accessibility | userPresence |
|---|---|---|
| `deviceId` (UUID) | `whenUnlockedThisDeviceOnly` | no |
| `deviceToken` (raw) | `afterFirstUnlockThisDeviceOnly` | no (background heartbeat needs it) |
| `deviceSecret` (raw, b64url) | `whenUnlockedThisDeviceOnly` + `SecAccessControl(.userPresence)` | yes (Face ID / passcode required to sign) |

Each scan-result HMAC sign triggers a biometric prompt the first time per
session; iOS caches the biometric authorization briefly so consecutive scans in
quick succession don't re-prompt. This is a deliberate UX/security trade-off.

### Universal Links + PKCE registration

The web auth callback is a custom-scheme URL
(`expresscan://register/callback?code=…`) matched by
`ASWebAuthenticationSession`'s `callbackURLScheme`. The HTTPS Universal Link
target (`https://manage.polaris.express/expresscan/register/callback?code=…`)
is still claimed in the AASA manifest as a belt-and-braces path — the iOS app
accepts either shape — but the production flow uses the custom scheme because
that's what works reliably.

> ⚠️ Universal Links **do not** fire from inside `ASWebAuthenticationSession`'s
> sandboxed web view — Apple deliberately suppresses them. Dismissal is driven
> exclusively by the session's `callbackURLScheme` (or, on iOS 17.4+, the
> `Callback` value). Earlier drafts of this doc claimed Associated Domains
> drove the dismissal; they did not.
>
> The iOS 17.4+ `.https(host:path:)` Callback was tried first — on iOS 26 it
> failed silently (`session.start()` returned true, no UI presented, completion
> handler never fired) despite a confirmed-correct AASA. Falling back to a
> custom scheme avoids the AASA-validation hot path entirely.

Flow:
1. `LoginViewModel.start()`:
   - Generate `codeVerifier` (32 random bytes, base64url).
   - Compute `codeChallenge = SHA256(codeVerifier)` (base64url).
   - Open `ASWebAuthenticationSession(url: registerURL, callbackURLScheme: "expresscan")`.
2. User signs in (or reuses the existing admin cookie session); the server's POST handler 302s the in-session web view to `expresscan://register/callback?code=…`.
3. AuthServices matches the scheme, dismisses the auth view, and invokes the completion handler with the URL. `LoginViewModel.extractCode(from:)` pulls out the `?code=…` query item and emits `deliveredCode`.
4. `RootCoordinator` transitions to `.registering(code, verifier)`, showing `RegistrationView`.
5. `RegistrationViewModel.submit()` POSTs `/api/devices/register` with `{oneTimeCode, codeVerifier, …}`.
6. On success, store `deviceId/Token/Secret` in Keychain, register for APNs, POST `/api/devices/{id}/push-token` from the priming step.

The custom scheme is **not** registered in `Info.plist` `CFBundleURLTypes` —
Apple does not require that for the auth-session path, and skipping registration
keeps stray `expresscan://` URLs from elsewhere from dispatching to the app.

The belt-and-braces `.onOpenURL` / `.onContinueUserActivity` path in `RootView`
only fires when the OS hands a stale HTTPS callback link to the app outside an
active auth session (e.g., the user taps an old email link); it should not fire
during the normal flow.

### SSE client

```swift
let (bytes, response) = try await urlSession.bytes(for: request)
guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw … }
var buffer = ""
for try await byte in bytes {
  buffer.append(Character(UnicodeScalar(byte)))
  if buffer.hasSuffix("\n\n") {
    yield(parseEvent(buffer))
    buffer = ""
  }
}
```

Reconnect with exponential backoff: 1s → 2s → 4s → 8s → 30s (cap), jittered
±25%. `Last-Event-ID` resume from the most recent `id:` field. The `for try
await` loop is bound to the view's `.task { }` block — view dismissal cancels
the task and closes the connection.

### Push handling

```swift
extension PushService: UNUserNotificationCenterDelegate {
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              didReceive response: UNNotificationResponse,
                              withCompletionHandler completion: @escaping () -> Void) {
    let info = response.notification.request.content.userInfo
    guard let pairingCode = info["pairingCode"] as? String,
          let deviceId = info["deviceId"] as? String,
          let purposeRaw = info["purpose"] as? String,
          let expiresAtMs = info["expiresAtEpochMs"] as? Int64 else {
      completion(); return
    }
    let request = ScanRequest(...)
    Task { @MainActor in
      coordinator.handleIncomingScanRequest(request, source: .push)
      completion()
    }
  }
}
```

Notification category registered at launch: `NFC_SCAN_REQUEST`, default tap
action only (no buttons). This keeps App Store review surface minimal.

### Heartbeat

While foregrounded:

```swift
Task { @MainActor in
  while !Task.isCancelled {
    try? await api.heartbeat()
    try? await Task.sleep(for: .seconds(60))
  }
}
```

While backgrounded: nothing. We do **NOT** use `BGAppRefreshTask` (per Apple HIG
audit recommendation — unreliable timing, marginal value). The 120s online
threshold accommodates a single missed beat; backgrounded phones go offline.

## UX details (from wireframes doc, locked)

- **Welcome:** one CTA "Sign in to ExpresSync." Logo + 96pt static NFC glyph.
- **Register:** prefill `UIDevice.current.name`, single rename field, "Register" button.
- **Notification priming:** before the system prompt, explain why.
- **Ready home:** 96pt animated NFC glyph (cyan, 0.8s pulse, halts on Reduce Motion), "Ready to Scan", status pill (with SF Symbol — color is NOT the only signal), "How this works" disclosure, footer Settings + Sign out.
- **Scan request:** glyph turns green and pulses faster (0.4s), countdown ring, dynamic subheading by purpose, "Tap to scan" button, Cancel.
- **System NFC sheet:** owned by iOS. We set `alertMessage` only; updates on state transitions (initial / reading / error).
- **Success:** big checkmark (spring animation), customer card with name + status badge + plan + renewal date. **Manual dismiss only — NO 5s auto-return.** "Scan another" / "Back to ready" buttons.
- **Error states:** clock (timeout, amber), shield (unsupported card, rose), cloud-off (network, rose), timer (pairing expired, amber), person-slash (token revoked, rose). Each has a specific recovery copy (see wireframes doc).

## Sign-out = deregister

Settings "Sign out" calls `DELETE /api/devices/{deviceId}` and clears all
Keychain entries. The two actions are unified — no concept of "signed out
locally but device still registered." This simplifies admin UX (no orphan
devices in the picker) per the UX validation recommendation.

## Offline scan queue

`ScanResultQueue` persists scan-result POST bodies that failed due to network
errors. Stored in `FileManager.default.urls(for: .applicationSupportDirectory)`
as JSON (small files, encrypted at rest by iOS file protection). On app
foreground / reconnect, attempts to deliver each in order with backoff. Shows
"N pending" badge on home screen.

If the pairing has already expired by the time we reconnect, the backend
returns 410 — we surface "Saved scan couldn't be delivered" briefly and
discard.

## Test plan

### Unit (`ExpresScanTests`)
- `ScanResultSignerTests`: known-vector tests against an independently computed reference (Python `hmac` module).
- `HexEncodingTests`: byte arrays round-trip to expected hex strings.
- `EventStreamServiceTests`: stub URLSession that streams pre-crafted SSE text; assert events parsed, `Last-Event-ID` tracked, reconnect backoff increases.
- `APIClientTests`: `URLProtocol` stub; assert 200 decode, 401 → AuthStore signal, 429 → `.rateLimited`, malformed JSON → `.decode`.
- `ScanCoordinatorTests`: drive state transitions via mocked services; assert coalescing dedups by pairingCode.

### UI (`ExpresScanUITests`)
- Onboarding flow (non-NFC): welcome → register → priming → ready.
- Settings: rename device, sign out confirmation.
- Error screens: each error state renders correct copy + actions.

### Manual test plan (tracked in `TestPlan.md`)
- DESFire card happy path.
- NTAG21x card happy path.
- MIFARE Classic rejection.
- Timeout (wait 60s).
- Cancel mid-scan.
- Push delivered while backgrounded → tap → scan.
- Foreground SSE delivery.
- Push + SSE coalescing (scan request received from both — only one prompt).
- Deregister from app → next API call clean.
- Deregister from portal → next bearer call → 401 → app logs out gracefully.
- APNs token rotation (uninstall + reinstall, verify token updates).
- Offline scan: airplane mode after card read, reconnect, scan delivered.
- VoiceOver pass on all screens.
- Dynamic Type at AX5: layouts don't break.
- Reduce Motion: animations replaced with static glow.

## Build & CI

- **GitHub Actions** workflow in `.github/workflows/ios-ci.yml`:
  - macos-15 runner.
  - Xcode 16.3 (default).
  - Build + run unit tests on PR.
  - On `main` push: archive + export IPA, upload to TestFlight via altool/Transporter.
- Two schemes: `ExpresScan-Debug` (sandbox APNs, dev backend) and `ExpresScan-Release` (prod APNs, prod backend).
- Code signing: automatic for v1; introduce fastlane match when 2+ engineers contribute.
- No SPM dependencies for v1. Manual SSE parser (~50 lines) avoids a third-party HTTP/SSE library.

## App Store readiness

- Demo video required (reviewers can't physically scan a card). Record:
  sign-in → register → admin sends scan from portal → push received → tap → NFC
  sheet → tap demo card → success screen. ≤3 minutes.
- App Privacy questionnaire: Device ID + User ID (push token, bearer resolves
  to user) — both linked, App Functionality, NOT for tracking. Card UID is
  user content, linked, App Functionality, NOT tracking. No location, health,
  financial.
- Subtitle: "NFC card reader for ExpresSync"
- Description (250 chars): "Turn your iPhone into an NFC card reader for ExpresSync. Sign in, register the device, and admin or self-triggered scans flow from the web portal to your phone in real-time."
