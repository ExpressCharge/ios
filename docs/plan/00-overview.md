# ExpresScan — Project Plan

ExpresScan is a native iPhone companion app for the **ExpresSync** EV charging
admin portal. It turns iPhones into first-class NFC tag readers alongside the
existing OCPP chargers, so an admin (or customer) can click "Scan tag" on the
website and have the iPhone read a card, returning the UID and enriched
customer/subscription info to the website.

This folder is the canonical plan, derived from a research+design pass with
9 specialist agents (architecture, backend API, frontend, iOS app architecture,
iOS UX/wireframes, Apple HIG expert, security audit, end-to-end UX researcher,
realtime infrastructure).

## Scope summary

The work spans **three repositories of code** (two existing, one new):

| Surface | Repo | Tracks |
|---|---|---|
| Backend (Fresh/Deno) | `../expresscharge` | Schema, bearer middleware, device endpoints, event bus additions, APNs publisher |
| Frontend (Fresh/Preact) | `../expresscharge` | Devices listing, device detail, picker rename, tap-target endpoint |
| iOS app (SwiftUI) | `./` (this repo) | Auth, NFC, SSE, APNs handling, success/error UX |

## Document index

- [`00-overview.md`](00-overview.md) — this file
- [`10-architecture.md`](10-architecture.md) — domain model, data flow, threat model summary
- [`20-contracts.md`](20-contracts.md) — canonical schemas, endpoints, event types, payload shapes (the **single source of truth** for cross-track contracts)
- [`30-backend.md`](30-backend.md) — backend implementation plan (expresscharge)
- [`40-frontend.md`](40-frontend.md) — frontend implementation plan (expresscharge)
- [`50-ios.md`](50-ios.md) — iOS app implementation plan (expresscan)
- [`60-security.md`](60-security.md) — non-negotiable security checklist
- [`70-build-sequence.md`](70-build-sequence.md) — parallelizable tracks, milestones, dependencies
- [`80-resolved-decisions.md`](80-resolved-decisions.md) — design questions where agents disagreed and how they were resolved

## Key decisions (one-line summary)

1. **Capabilities model:** new `devices` table + `device_tokens`; chargers stay in `chargers_cache`; a Postgres `tappable_devices` view unions them by capability.
2. **Auth:** admin login goes through **Pocket ID OIDC** (with email/password as a configurable break-glass fallback); customer login is unchanged (magic link / scan-to-login). The iOS app is **admin-only** and uses device-bound bearer tokens (`Bearer dev_…`), SHA-256 hashed at rest, paired with a per-device `deviceSecret` for HMAC nonces. **Universal Links + PKCE** for the registration callback (not custom URL scheme).
3. **Scan delivery:** SSE-first while foregrounded, visible APNs push (`time-sensitive`, `apns-collapse-id`) when backgrounded. Phone coalesces by `pairingCode`.
4. **Scan result return:** new `POST /api/devices/scan-result` (NOT reusing `/api/ocpp/pre-authorize`). Publishes the existing `scan.intercepted` event so the website's scan modal needs no changes.
5. **Frontend:** new `/admin/devices` page (accent `teal`); `/admin/chargers` stays charger-only; the scan-modal picker becomes a tap-target picker that groups chargers + phones.
6. **iOS:** SwiftUI + iOS 17, `NFCTagReaderSession` with `[.iso14443, .iso15693]`, no auto-dismiss success, drop `BGAppRefreshTask`, biometric-gate the device secret.
7. **Migration:** the system is not live yet, so we ship breaking changes directly — no feature flags, no compatibility shims, no sibling endpoints. We rename `chargers_cache` → `devices` (with a `kind='charger'` row per existing entry), generalize `scan-pair` → `device-scan` namespace, and replace `/api/auth/scan-charger-list` with `/api/auth/scan-tap-targets`. `/api/ocpp/pre-authorize` stays (it's a SteVe contract).

## Non-goals (v1)

- Charger migration into a unified `devices` table.
- HCE / Apple Pay-style emitting.
- Live Activities / Dynamic Island.
- Multi-tenant features (single-tenant assumption confirmed).
- Customer-facing self-registration of phones (admin-only registration flow in v1; flag for v1.1).
- Localization (en-only; structured for future i18n).
