# Build Sequence (Parallelizable Tracks)

Five parallel tracks, with explicit cross-track dependencies. Total estimated
work: 4-6 weeks of focused engineering.

## Shared contracts (must land first, in this order)

These are the cross-track contracts. Lock them down BEFORE any track diverges:

1. `src/lib/types/devices.ts` — TypeScript types per [`20-contracts.md`](20-contracts.md).
2. `drizzle/0032_devices_and_tokens.sql` — schema + admin-owner trigger.
3. `drizzle/0033_tappable_devices_view.sql` — union view.
4. `EventBusEventType` additions in `src/services/event-bus.service.ts`.
5. `selectAuth` skeleton in `_middleware.ts` (rejects bearer on admin routes; routes correctly to either branch).

These are landed by **Track A (one engineer)** in week 1. Once merged, the
other tracks unblock.

## Track A — Backend foundations + Pocket ID OIDC

**Owner:** one backend engineer.

- [ ] A1. Schema migrations (`devices`, `device_tokens`, view, role-trigger).
- [ ] A2. Drizzle types + shared `src/lib/types/devices.ts`.
- [ ] A3. Event-bus type additions.
- [ ] A4. `selectAuth(route)` function in `_middleware.ts`; bearer-resolution branch.
- [ ] A5. Audit log additions (new event types in `src/lib/audit.ts`).
- [ ] A6. Pocket ID OIDC plugin (env-gated; JIT provisioning hook).
- [ ] A7. 3-mode admin login UI (`routes/login.tsx` + `routes/login/email.tsx`).
- [ ] A8. Unit tests: bearer rejection on admin routes; HMAC compute/verify.

## Idempotency note (applies to Tracks B + C)

Every state-changing endpoint added in Tracks B and C MUST wrap its handler
in `withIdempotency(ctx, "<route-path>", async () => { … })` from the
existing `src/lib/idempotency.ts`. See `20-contracts.md` §
"Idempotency-Key support" for the route list and rationale.

## Track B — Device REST endpoints

**Owner:** one backend engineer (can be the Track A engineer after A is done,
or a parallel one starting once shared contracts are merged).

**Depends on:** Track A complete.

- [ ] B1. `POST /api/devices/register` (PKCE one-time-code exchange).
- [ ] B2. `POST /api/devices/heartbeat`.
- [ ] B3. `DELETE /api/devices/{deviceId}` (self-deregister).
- [ ] B4. `PUT /api/devices/{deviceId}/push-token`.
- [ ] B5. `GET /api/devices/me`.
- [ ] B6. `GET /api/admin/devices` (list with filters).
- [ ] B7. `GET /api/admin/devices/{deviceId}` (detail).
- [ ] B8. `POST /api/admin/devices/{deviceId}/deregister`.
- [ ] B9. `POST /api/admin/devices/{deviceId}/rename`.
- [ ] B10. `GET /api/auth/scan-tap-targets` (replaces scan-charger-list).
- [ ] B11. Integration tests for full registration + heartbeat lifecycle.

## Track C — Scan-trigger plumbing + APNs

**Owner:** one backend engineer.

**Depends on:** Track A complete; Track B can be in parallel.

- [ ] C1. APNs HTTP/2 client + JWT signer (`src/lib/apns.ts`).
- [ ] C2. `POST /api/admin/devices/{deviceId}/scan-arm` (publishes `device.scan.requested` event + sends APNs).
- [ ] C3. `DELETE /api/admin/devices/{deviceId}/scan-arm`.
- [ ] C4. `GET /api/devices/scan-stream` (SSE; per-device kick-off).
- [ ] C5. `POST /api/devices/scan-result` (HMAC verify, atomic claim, publish `scan.intercepted`, return enriched).
- [ ] C6. `GET /api/devices/scan-result/{pairingCode}` (polling fallback).
- [ ] C7. Generalize `/api/auth/scan-detect` to accept `deviceId` OR `chargeBoxId`.
- [ ] C8. Generalize `scan.intercepted` payload (drop legacy `chargeBoxId` field; `pairableType` + `pairableId` only).
- [ ] C9. Universal Links manifest at `routes/.well-known/apple-app-site-association.json`.
- [ ] C10. End-to-end integration test: arm → SSE → scan-result → enriched → modal-side `scan.intercepted`.

## Track D — Frontend (admin Devices surface + picker rename)

**Owner:** one frontend engineer.

**Depends on:** A1, A2, A3 (schema + types) for B6/B7 to exist as mocks. Can
start with stubs.

### Phase D1: refactors (no behavior change)

- [ ] D1a. Rename `islands/shared/charger-visuals.ts` → `device-visuals.ts`; add `normalizeDeviceStatus`, `DEVICE_STATUS_HALO`.
- [ ] D1b. `src/lib/utils/device-icons.ts` — `getDeviceIcon` resolver.
- [ ] D1c. `components/devices/CapabilityPill.tsx`.
- [ ] D1d. `components/brand/devices/IPhoneIcon.tsx`, `LaptopIcon.tsx`.
- [ ] D1e. Update `ChargerCard` to use `getDeviceIcon`.
- [ ] D1f. Copy fix: "Connecting…" in `ScanPanel`.
- [ ] D1g. Publish `docs/design-tokens.json` for iOS team.

### Phase D2: new admin Devices surface

- [ ] D2a. `components/devices/DevicesStatStrip.tsx`.
- [ ] D2b. `components/devices/DeviceIdentityCard.tsx`.
- [ ] D2c. `components/devices/DeviceFiltersBar.tsx`.
- [ ] D2d. `islands/DeviceCard.tsx`.
- [ ] D2e. `islands/devices/DeviceActionsMenu.tsx`.
- [ ] D2f. `routes/admin/devices/index.tsx`.
- [ ] D2g. `routes/admin/devices/[deviceId].tsx` (with charger redirect).
- [ ] D2h. Sidebar nav entry in `src/lib/admin-navigation.ts`.

### Phase D3: scan modal picker swap

- [ ] D3a. `components/scan/DevicePickerInline.tsx`.
- [ ] D3b. Refactor `useScanTag` hook: `chargeBoxId` → `deviceId`, `resolveChargeBoxId` → `resolveTapTargetDeviceId`.
- [ ] D3c. Update `TapToAddModal` and all callers.
- [ ] D3d. Delete `ChargerPickerInline` and `scan-charger-list` references.
- [ ] D3e. Per-kind copy in `ScanPanel`'s `armed` state.

## Track E — iOS app

**Owner:** one iOS engineer.

**Depends on:** shared contracts (`docs/plan/20-contracts.md`) and Track A
endpoints (for live testing). Can start scaffolding day 1 with stubs.

### Phase E1: scaffold + design system

- [ ] E1a. Xcode project + targets + entitlements + Info.plist + privacy manifest.
- [ ] E1b. `Theme.swift` + `Assets.xcassets` Color Sets per design tokens.
- [ ] E1c. `KeychainStore.swift` + `AuthStore.swift`.
- [ ] E1d. `APIClient.swift` skeleton with bearer auth.
- [ ] E1e. `ScanResultSigner.swift` + tests against known vectors.

### Phase E2: registration + onboarding

- [ ] E2a. `WelcomeView` + `LoginViewModel` (ASWebAuthenticationSession).
- [ ] E2b. `RegistrationView` + PKCE generation + `/devices/register` exchange.
- [ ] E2c. `SceneDelegate` Universal Link routing.
- [ ] E2d. `NotificationPrimingView` + `PushService` (APNs registration + push-token upload).

### Phase E3: scan flow

- [ ] E3a. `EventStreamService` (SSE client, AsyncSequence, reconnect).
- [ ] E3b. `NFCService` (`NFCTagReaderSession` wrapper, tag-type dispatch, hex encoding, MIFARE Classic rejection).
- [ ] E3c. `HeartbeatService` (60s loop while foregrounded).
- [ ] E3d. `ScanCoordinator` state machine + coalescing.
- [ ] E3e. `ReadyView`, `ScanActiveView`, `SuccessView`, `ErrorView`.
- [ ] E3f. `ScanResultQueue` (offline persistence + retry).

### Phase E4: settings + polish

- [ ] E4a. `SettingsView` + sign-out (= deregister) flow.
- [ ] E4b. `DiagnosticsSheet`.
- [ ] E4c. Accessibility pass: VoiceOver labels, Dynamic Type, Reduce Motion, color-+-symbol redundancy.
- [ ] E4d. App Store assets (screenshots, demo video, App Privacy questionnaire).

## Cross-track milestones

| Milestone | Tracks completed |
|---|---|
| **M1: Shared contracts merged** | A1–A5 |
| **M2: Backend has working device registration end-to-end** | A1–A8, B1–B5 |
| **M3: Scan flow works (curl-driven, no iPhone)** | C1–C10 |
| **M4: Admin can see/manage devices in the web portal** | B6–B11, D2 |
| **M5: iOS app can register with the backend (cold-launch → token)** | E1–E2 |
| **M6: End-to-end scan: web click → iPhone reads card → enriched UI** | E3 + everything above |
| **M7: Picker is unified; chargers live alongside phones** | D1, D3 |
| **M8: Production-ready (App Store submission, accessibility, demo video)** | E4 |

## Suggested team allocation

For 1-2 engineers: Tracks A → B → C → D → E in sequence (with D starting in
parallel once A is merged). 6-8 weeks calendar time.

For 3-4 engineers: A (1 eng, week 1), then B+C parallel (1 eng each), D (1
eng), E (1 eng) all running concurrently from week 2. 4-5 weeks calendar time.

For 5+ engineers: split B and D into parallel sub-tracks (B-lifecycle vs
B-admin-management; D2 and D3 in parallel). 3-4 weeks calendar time.
