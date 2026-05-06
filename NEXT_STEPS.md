# Next Steps — ExpresScan iOS

The implementation phase is complete on this machine: SwiftPM library targets
build and test cleanly here, the SwiftUI app target source tree is written
and committed, and the backend the app talks to is live on `expresscharge/main`.
Everything below either requires a developer Mac with full Xcode 16+, an
Apple Developer portal session, or a physical iPhone — i.e. the work that
couldn't be done on the orchestrator's machine.

## Wave 6 — ExpressCharge (in development)

Wave 6 expands the app to the customer-style ExpressCharge product:
capability-driven Scan + Chargers tabs, charger remote-control, kiosk
mode, remote-managed settings, ExpressCharge rebrand. Branch
`wave-6-capabilities-chargers` carries the work; design summary is in
[`docs/plan/85-wave6.md`](docs/plan/85-wave6.md). Local pre-commit
verification: `bin/precommit.sh`.

Steps are listed in priority order; **1–8** are the fastest path to a
working build on a real iPhone. The rest can follow.

## On a developer Mac (Xcode 16+)

### 1. Set up the project

```sh
git clone <expresscan remote>
cd expresscan
brew install xcodegen
xcodegen generate
open ExpresScan.xcodeproj
```

### 2. First compile pass

Estimated **3–5 hours** of mechanical fix-ups (per the E-app-wire agent's
report; well within the planned 4–8 h budget).

- **Swift 6 strict-concurrency tweaks** (~2 h): `@Sendable` / `nonisolated` /
  `MainActor.assumeIsolated` adjustments, especially around
  `ScanCoordinator.startConnecting` (the three sibling `Task { ... }` blocks)
  and the `onSuccess` closure in `HeartbeatService.start`.
- **`@Observable` + `@MainActor` interaction** (~30 min): the
  `ScanCoordinator.scan` property of `RootCoordinator` is read from
  `ReadyView` and `DiagnosticsSheet`; SwiftUI may need explicit `@Bindable`
  or `coordinator.scan?.state` re-keying if Xcode's strict tracking
  complains.
- **`UNUserNotificationCenterDelegate` + `@MainActor` AppDelegate** (~30 min):
  may need `nonisolated` on the two delegate callbacks and
  `Task { @MainActor in … }` wrappers under
  `SWIFT_STRICT_CONCURRENCY = targeted`.
- **`DeviceMeResponse` shape** (~30 min): `SettingsViewModel` declares a
  local mirror; field names may need to align with what
  `GET /api/devices/me` actually returns.
- **`NFCReaderError.Code` cases** (~15 min): a couple of error symbols
  occasionally rename between Xcode SDK versions
  (`readerSessionInvalidationErrorFirstNDEFTagRead`,
  `readerSessionInvalidationErrorSessionTerminatedUnexpectedly`).
- **`TimelineView(.animation)` interval** (~15 min): minor tweak if 30 fps
  feels jittery on-device.
- **`ExpresScanTests` host-app linkage** (~30 min): `BUNDLE_LOADER` /
  `TEST_HOST` paths in `project.yml` may need adjusting after the first
  `xcodegen generate` run.
- **`registerForRemoteNotifications` Sendable boundaries** (~10 min): may
  surface a warning around the `UIApplication.shared` access in
  `RegistrationViewModel`.

### 3. Verify

```sh
xcodebuild test -scheme ExpresScan-Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Apple Developer portal setup

### 4. Register the App ID

- Bundle ID: `com.example.expresscharge.ios`
- Team: `ABC1234XYZ`
- Capabilities: **Near Field Communication Tag Reading**, **Push
  Notifications**, **Associated Domains**

### 5. Generate APNs auth key (P8)

Add to the **backend** env vars (in `expresscharge`):

```
APNS_KEY_ID=…       # 10-char Apple-issued key id
APNS_TEAM_ID=ABC1234XYZ
APNS_KEY_BASE64=…   # base64 of the .p8 PEM
APNS_TOPIC=com.example.expresscharge.ios
```

Recipe for the base64 step: `base64 -i AuthKey_<KEYID>.p8`.

### 6. AASA domain validation

Apple's CDN (`app-site-association.cdn-apple.com`) fetches
`https://manage.example.com/.well-known/apple-app-site-association` at
install time. Verify that the production deploy serves it `200 OK` with
valid JSON, no auth, no redirects:

```sh
curl -sI https://manage.example.com/.well-known/apple-app-site-association
curl -s  https://manage.example.com/.well-known/apple-app-site-association | jq .
```

The route is at `routes/.well-known/apple-app-site-association.ts` (Fresh v2
doesn't auto-serve `.json` files, so we ship a small handler that reads the
adjacent `.json` file).

## End-to-end test against your local backend

### 7. Run the backend

```sh
cd ../expresscharge
docker compose up -d
```

### 8. Run the app on a real iPhone

NFC sessions do not work on the simulator — needs hardware.

- Sign in via in-app web view → admin login flow → register the device.
- Trigger a scan from the admin portal (`/admin/devices/{id}` → "Trigger
  scan", or via the command palette's "Scan Tag" action).
- Push notification should arrive → tap → NFC sheet opens.
- Tap a real DESFire or NTAG card; UID flows back; success screen renders
  enriched customer + subscription info.
- Edge cases to verify:
  - MIFARE Classic rejection (friendly error message).
  - 20-second timeout when no card taps.
  - Cancel from the system NFC sheet.
  - Network error after the read (queue + retry on reconnect).
  - Sign-out from Settings: `DELETE /api/devices/{id}` lands before
    Keychain wipe, the app returns to Welcome.
  - Token revoked from the admin portal: next API call returns 401, app
    falls back to Welcome with a one-time toast.

## App Store / TestFlight

### 9. Replace the placeholder AppIcon

`App/Resources/Assets.xcassets/AppIcon.appiconset/` currently contains a
placeholder. The brand asset is the 40×40 yellow lightning-E in the sister
repo at `../expresscharge/static/logo.svg`. Resize / re-export to all the
required app-icon dimensions and drop them in.

### 10. App Store Connect

- **Title:** "ExpresScan"
- **Subtitle:** "NFC card reader for ExpresSync"
- **Description (~250 chars):** "Turn your iPhone into an NFC card reader
  for ExpresSync. Sign in, register the device, and admin or self-triggered
  scans flow from the web portal to your phone in real-time."
- **App Privacy questionnaire:**
  - Device ID (push token) — collected, linked to user, App Functionality,
    NOT for tracking
  - User ID (bearer-token-resolved user) — collected, linked, App
    Functionality, NOT for tracking
  - Other User Content (card UID, transient, never persisted on device) —
    collected, linked, App Functionality, NOT for tracking
  - All other categories: No.

### 11. Demo video for App Review

Reviewers can't physically scan a card; a video is mandatory on first
submission. Record (≤3 min):

1. Sign-in.
2. Device registration.
3. Admin triggers a scan from the web portal.
4. Push notification arrives.
5. Tap → NFC system sheet opens.
6. Tap a card → success screen with enriched info.

Include a demo account + a sample card UID in App Review Notes.

### 12. TestFlight upload

```sh
xcodebuild archive -scheme ExpresScan-Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/ExpresScan.xcarchive
xcodebuild -exportArchive \
  -archivePath build/ExpresScan.xcarchive \
  -exportOptionsPlist exportOptions.plist \
  -exportPath build/ipa
xcrun altool --upload-app -f build/ipa/ExpresScan.ipa \
  --apiKey $APP_STORE_CONNECT_API_KEY_ID \
  --apiIssuer $APP_STORE_CONNECT_ISSUER_ID
```

(Or use Transporter.app for a GUI workflow.)

## Repo hygiene

### 13. Set up the expresscan remote

Currently local-only — no `origin` configured. Pick a host and push:

```sh
cd expresscan
git remote add origin git@github.com:vladzaharia/expresscan.git  # or wherever
git push -u origin main
```

The repo currently has three commits on `main`:

```
f5b30ce Wave 4 E-app-wire: ScanCoordinator + NFC/Push/Heartbeat/SSE/Queue services
f10a381 Wave 3 E-app-skel: SwiftUI app target skeleton + xcodegen project
ea65083 Initial scaffold of E-pkg: pure-Swift libraries + tests
```

## Optional polish (defer until v1.1 unless you want it)

- **Localizable.strings extraction.** v1 ships English hard-coded; the
  views are written so a `String(localized:)` pass is mechanical.
- **Live Activity / Dynamic Island** for in-flight scans (countdown ring
  in the Dynamic Island while the scan request is open).
- **App Intents** for Siri / Shortcuts ("Hey Siri, ready to scan" →
  pre-arms the foreground state).
- **Lock-screen widget** showing connection status + last-scan timestamp.
- **Real `ExpresScanTests` / `ExpresScanUITests`.** A placeholder target
  exists; fill it in once the project compiles cleanly.
- **Diagnostics sheet "Test scan" wiring.** Currently issues a heartbeat;
  could send a self-arm to exercise the full SSE → NFC path without
  needing the web portal.

## Reference

- Full plan: [`docs/plan/`](docs/plan/) (10 files)
- Approved execution choreography: `~/.claude/plans/create-a-plan-to-refactored-storm.md`
- Project status / decisions in agent memory:
  `~/.claude/projects/-Users-scruffy-Documents-Repos-expresscan/memory/`
