# Wave 6 — Capabilities, Chargers Tab, Remote Settings, Kiosk

> **Status:** in development on branch `wave-6-capabilities-chargers` (both repos). Not yet pushed/deployed.

Wave 6 expands ExpresScan from an admin-only NFC scanner into a capability-driven mobile front-end for the EV charging platform. The user-visible product is rebranded **ExpressCharge**.

## Goal

Three roles, one app, gated by capabilities the server pushes down:

| Role | Capabilities | iOS surface |
|------|-------------|------------|
| Admin operator | `{scanner, user}` (most common) | Both Scan + Chargers tabs |
| Future customer (admin-exposed today) | `{user}` | Chargers tab only |
| Single-purpose appliance | one of `{scanner, user}` + `kiosk` | Lone screen, no chrome, no settings |

## Capability set

`{scanner, charger, user, kiosk}` — flat enum, server-side validated. Renamed from the legacy `{tap, ev}` in migration `0037`.

- `scanner` *(was `tap`)* — device performs NFC tap.
- `charger` *(was `ev`)* — device IS a charging station. Auto-managed; only on `kind='charger'` rows; never editable.
- `user` — Chargers tab access (list, detail, start/stop, cancel reservation).
- `kiosk` — single-screen appliance UI; legal only paired with exactly one of `{scanner, user}`.

Apps cannot self-register as chargers — registration rejects `'charger'` in `requestedCapabilities` with 400 `capability_not_app_eligible`. The CHECK constraint `'charger' = ANY(capabilities) ⟺ kind = 'charger'` enforces it at the DB layer.

## Architecture

### Backend (expresscharge, Deno + Fresh + Drizzle)

- **Migrations:**
  - `0036_devices_kind_tablet_nfc.sql` *(landed independently)* — adds `tablet_nfc` to the `devices.kind` CHECK.
  - `0037_capabilities_rename.sql` — renames `tap`→`scanner`, `ev`→`charger` in capability arrays; rebuilds `tappable_devices` view; adds CHECK forbidding legacy + `'charger'` on apps.
  - `0038_settings_and_capability_invariants.sql` — adds `device_settings` (LWW table: `device_id, key, value_json, updated_at, updated_by`) + kiosk-legality CHECK (`kiosk` requires XOR of scanner/user).

- **Capability gate** (`src/lib/devices/capability-gate.ts`) — `requireCapability(ctx, ...caps)` 403s with `device.capability.denied` audit on miss. `validateCapabilitySet` enforces kiosk legality.

- **Settings reconciliation** (`src/lib/devices/lww.ts`) — pure `mergeSettings(local, remote)` per-key timestamp LWW with server tie-break + `clampClientUpdatedAt(client, now+5s)` future-stamp clamp.

- **Sync endpoint** — `GET /api/devices/me/state` returns the full `DeviceState` envelope (identity, capabilities, kioskAllowed, settings, scanStatus, pushToken (last-8 only), connectivity). `POST /api/devices/me/state/sync` accepts `pendingSettings` + diagnostics, merges via LWW, returns the same envelope. Replaces the deleted `POST /heartbeat`.

- **Admin App Configuration** — extends `/admin/devices/:id` with capability multi-select, settings editor, diagnostics readout. Three new admin-cookie endpoints: `PATCH /capabilities`, `PATCH /settings`, `GET /configuration`. Both PATCH endpoints emit `device.capabilities.changed` / `device.settings.changed` SSE events filtered to the device's own stream.

- **Charger control** — six new bearer-auth endpoints under `/api/admin/devices/{id}/`: `start`, `stop`, `cancel-reservation`, `session`, `tags`, `reservations`. All gated on `user` capability; offline-charger preflight returns 409 `charger_offline`. Idempotent via `withIdempotency`. Audit: `device.user.{start_charge|stop_charge|cancel_reservation}`.

- **Charger list** — `GET /api/devices` (bearer + `user`) returns the org's chargers via `tappable_devices` filtered to `kind='charger'`, joined to `chargers_cache` for friendly_name + form_factor + last_status. 90s online window.

- **Reservation default-tag** — admin reservation-create defaults `idTag` / `tagPk` to the creator's first active tag mapping; falls back to `admin-blackout` when the admin has no tags.

### iOS (ExpresScan, SwiftUI + iOS 26)

- **Pure-Swift modules** (`Sources/`):
  - `Capabilities` — `DeviceCapability` extension (legality + derivations) + `CapabilityMetadata` registry.
  - `DeviceSync` — `DeviceState` envelope, `SyncRequest`, `SettingsReconciler` (LWW merge), `SettingsStore` actor (atomic on-disk JSON), `CapabilityCache` (UserDefaults-backed cold-launch cache).

- **App shell** (`App/Features/Tabs/`) — native iOS-26 liquid-glass `TabView` with two tabs: **Scan** + **Chargers**. Tab bar appears only when both `scanner` AND `user` are present; otherwise the lone capability's screen is the root. `KioskShell` (with the hidden 5-tap-corner escape gesture to Diagnostics) wraps the lone view when `kiosk` is set.

- **Settings + Diagnostics** — moved to a top-right toolbar gear button. `SettingsView`'s top "Connectivity" section shows status; Diagnostics is a `NavigationLink` push (no longer a sheet) and surfaces the connected server URL.

- **Registration capability picker** (`App/Features/Registration/CapabilityPickerSection.swift`) — multi-select toggles (default `{scanner, user}`); inline kiosk-legality validation; Form-converted for native keyboard avoidance. User-assigned-device-name entitlement requested.

- **Chargers tab** (`App/Features/Chargers/`) — `ChargerListViewModel` + `ChargersTabView` + `ChargerListRow` + `ChargersFilterMenu`. Native `List` + `.refreshable` + `ContentUnavailableView` + online-status `Menu` filter.

- **Charger detail** (`App/Features/Chargers/ChargerDetailView.swift`) — customer-style: `StatusHero` (big tinted-glass card) + `LiveTelemetryRow` (three `BigStatNumber` columns, kWh/kW/elapsed, `.contentTransition(.numericText())`) + `ReservationsCard` + `TagPickerSheet`. `PrimaryButton.Size.hero` (~80pt) for Start/Stop. Path A start uses the reservation's bound tag (looked up via `/tags`); Path B opens the picker.

- **DeviceStateCoordinator** (`App/Services/DeviceStateCoordinator.swift`) — drives the 60s `me/state/sync` loop while in foreground, reads cached capabilities on cold launch, routes `device.capabilities.changed` and `device.settings.changed` SSE events to live state, fires immediate sync on foreground transition. Replaced the deleted `HeartbeatService`.

- **Scan UI polish** (slice N + N+1) — matched-geometry icon morph between Ready and ScanActive; pulse + tint-to-green when armed; `CountdownRing` wind-up sweep; `CompactCountdown` toolbar indicator (green on Scan, white on result views). Result views show colored check/x (blue/green/yellow/red) by subscription status; auto-dismiss after 10s via top-right ring; native top-left back button; bottom footer with card ID (left) + card type (right).

- **Rebrand** (slice L0) — `CFBundleDisplayName` → "ExpressCharge", Welcome copy rewritten neutral-friendly, `Wordmark`/`BrandLogo` defaults updated, generated `AppIcon.appiconset` from `expresscharge/app-icons/ios/`. Project folder + bundle ID stay as `ExpresScan` / `gg.vlad.expresscan`.

## Rollout

- **Hard cutover.** Single client (the user's iPhone). Server deploys first; iOS rebuilds via TestFlight afterward. Legacy heartbeat path is deleted in the same PR. No `tap`-or-`scanner` dual-accept window.

- **No CI gate** in this PR. `bin/precommit.sh` in each repo is the standard local recipe (swift test + banned-imports + xcodebuild test on iOS; deno check + deno test + migration smoke on the server). GitHub Actions wiring is a follow-up PR.

## Verification gates (pre-deploy)

1. iOS: `bin/precommit.sh` green (SwiftPM 91 tests, ExpresScanTests minus 3 pre-existing ScanCoordinator flakes, banned-imports clean).
2. expresscharge: `bin/precommit.sh` green (deno check, deno test minus the pre-existing `scan-login HMAC mismatch returns 403` flake, migration 0036→0038 applies cleanly).
3. iOS app target builds on iOS 26 simulator via xcodebuild.
4. Manual QA on iPhone via TestFlight (per the plan's manual-QA checklist).

## Known follow-ups

- **GitHub Actions CI** — formalize `bin/precommit.sh` into a workflow.
- **3 pre-existing `ScanCoordinatorTests` flakes** — the tests expect `.scanRequested` but get `.scanning` (Wave 5's auto-NFC behavior moved the state machine further). Update the tests.
- **Customer-token mint endpoint** — schema-only today (token is just a token; admin/customer derived from linked user role); the mint flow + customer-portal "Get the app" entry point are a follow-up PR.
- **Per-row owner scoping for `user` actions** — today `user` cancels any reservation. When customer flow ships, narrow to own resources.
- **Live Activities + Dynamic Island for active charging** — flagged in the UX research; high-impact iOS-26 polish, deferred.
- **App Intents** for "Start charging at \(charger)" / "Stop charging" — flagged; ~1 day.
- **Connector-type + max-amperage on `chargers_cache`** — the wire shape carries them as nullable; populating them needs StEvE-side metadata or a manual override path in the App Configuration tab.
- **iPad landscape** — currently locked to portrait-only via `UISupportedInterfaceOrientations~ipad`. Landscape iPad is a follow-up.
