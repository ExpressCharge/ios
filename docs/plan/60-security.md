# Security Checklist (Non-Negotiable)

Derived from the security audit pass. Every item below MUST be implemented and
verified in the implementation phase. Items marked **HIGH** would create direct
vulnerabilities; **MED** items are defense-in-depth; **LOW** items are
accepted-risk decisions documented for future reference.

## 1. Token issuance

- **HIGH** Universal Links + PKCE for the registration callback (NOT custom URL
  scheme). The registration request includes `oneTimeCode` + `codeVerifier`;
  server verifies `SHA256(codeVerifier) === storedCodeChallenge`.
- **HIGH** One-time code stored as a hashed row in `verifications` (identifier
  `expresscan-register:{userId}:{hashedCode}`), atomic-claimed via
  `UPDATE … WHERE status='armed' RETURNING` (mirrors `scan-login.ts:222`).
- **HIGH** `deviceToken` and `deviceSecret` returned **only** in the POST
  `/api/devices/register` response body. Never in URL/redirect, query string,
  log line, or audit table. Response: `Cache-Control: no-store, Pragma: no-cache`.
- **HIGH** Logger middleware MUST redact `Authorization` headers and
  registration-response bodies. Verify before deploy.
- **MED** Document the migration path to per-device asymmetric keys (Ed25519 in
  Secure Enclave) for v2; store `device_pubkey TEXT NULL` in schema now to make
  the upgrade path painless.

## 2. Token storage on device

- **HIGH** `deviceToken` Keychain accessibility:
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (background heartbeat needs
  it). `kSecAttrSynchronizable=false`.
- **HIGH** `deviceSecret` Keychain accessibility:
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` + `SecAccessControl(.userPresence)`.
  Each scan-result HMAC sign triggers a biometric prompt (cached briefly by iOS).
- **LOW** Jailbreak risk accepted; document.

## 3. Token transport

- **HIGH** Token always in `Authorization: Bearer dev_…` header. Never URL,
  query string, or body.
- **MED** Cert pinning deferred to v2 (operational complexity outweighs the
  marginal benefit at this risk profile).

## 4. Token revocation

- **HIGH** Mid-stream revocation: `device.token.revoked` event published when
  any of (admin force-deregister, device DELETE, expiry) fires. SSE stream
  subscribes; on receipt with matching `tokenId`, emit `event: revoked` and
  close.
- **HIGH** App on receipt of `event: revoked` OR a 401 on any bearer route:
  clear all Keychain entries, return to welcome screen, show one-time toast
  "An admin signed this device out. Sign in again."

## 5. Scan-arm authorization

- **HIGH** Owner-self-arm is the default. An `owner_user_id` can always arm
  scans on their own device.
- **HIGH** Admin-initiated arming on a device they don't own requires the
  owner to have toggled `admin_arm_allowed = true` in device settings (default
  off). Send a visible push with the requester's identity, show explicit
  "Allow" UI in the app for v1.1 — v1 just rejects with 403 if owner is not
  the requester.
- **HIGH** Audit `device.scan.armed` with `armed_by_user_id` and
  `target_device_id` always. Anomaly alerting on cross-user arms.

## 6. Scan-result HMAC

- **HIGH** Domain separation: `deviceSecret` used ONLY for scan-result nonces.
  Sign message: `"scan-result/v1|" + idTag + "|" + pairingCode + "|" + deviceId + "|" + ts`.
- **HIGH** Replay window: 60s (matches existing `scan-login` REPLAY_WINDOW_MS).
- **HIGH** Constant-time HMAC compare (reuse `constantTimeEqual` from
  `scan-login.ts:100`).
- **HIGH** Atomic single-use claim of pairing row (mirror existing pattern).
- **HIGH** `idTag` normalized to hex uppercase before HMAC compute, on both
  sides. (Backend: `idTag.toUpperCase()`. iOS: `String(format: "%02X", byte)`.)

## 7. Push notification security

- **MED** Push payload includes `pairingCode` (single-use, 90s TTL, useless
  without bearer + secret). Acceptable lock-screen disclosure risk.
- **LOW** Push tokens stored in `devices.push_token`. DB dump risk: leaks
  push-target identity but cannot push without our APNs key. Documented.
- **MED** Both push (when bgd) and SSE (when fgd) deliver the arm event. App
  coalesces by `pairingCode`. Backend doesn't suppress duplicate delivery
  (NSE-based suppression is fragile).

## 8. SSE stream security

- **HIGH** Per-device concurrent stream cap = 1 (kick-off via
  `device.session.replaced`). Per-IP cap = 3 (matches existing pattern).
- **HIGH** Replay buffer filter: when replaying buffered events on `Last-Event-ID`
  reconnect, filter by **both** `device_id` AND `pairingCode` (mirror
  `scan-detect.ts:269-271`).
- **MED** TCP keepalive enabled with 30/10/3 timing for dead-peer detection.
  Hard idle ceiling 90s as backup.

## 9. Origin/CSRF

- **HIGH** Single `selectAuth(route)` function in `_middleware.ts` is the only
  source of truth for which scheme is accepted AND whether origin is enforced.
- **HIGH** `/api/admin/*` MUST reject bearer auth (returns 401 if
  `ctx.state.device` set but `ctx.state.user` not). Unit-tested.
- **HIGH** `/api/devices/*` (except `/register`) accepts bearer ONLY (no cookie
  fallback). `/api/devices/register` accepts cookie ONLY.
- **HIGH** Origin-exemption is derived from `selectAuth` returning `bearer`,
  not maintained as a parallel allow-list.

## 10. PII / data minimization

- **MED** Enriched scan-result returns minimum: `customer.displayName`,
  `customer.slug`, `subscription.planLabel`, `subscription.status`,
  `subscription.currentPeriodEndIso`, `subscription.billingTier`. Drop any
  field not directly used in the iPhone success screen UI.
- **MED** iPhone holds enriched result **in-memory only**. No `UserDefaults`,
  no Core Data, no log statement. On screen dismiss, the in-memory reference
  is dropped.
- **HIGH** Audit `device.scan.completed` with `idTagPrefix: idTag.slice(0,4)`
  only. Never full UID in audit/logs (matches `scan-login.ts:293`).

## 11. Backend changes' impact on existing security

- **HIGH** Existing cookie auth on `/api/admin/*`, `/api/customer/*`,
  `/api/auth/*` paths: no behavior change.
- **HIGH** `/api/ocpp/pre-authorize` HMAC-signed endpoint: untouched. Phone
  scan-result MUST NOT funnel through it. Document the boundary in the route
  file's header comment.
- **HIGH** Cookie session enforces existing 8-hour customer ceiling. Bearer
  tokens have a 365-day expiry but are revocable.

## 12. Audit & monitoring

- **HIGH** New audit event types added to `auth_audit` (or a new
  `device_audit` table mirroring its schema):
  - `device.registered` (actor=user, target=deviceId, ip, ua, app_version)
  - `device.deregistered` (actor user/admin, reason, ip)
  - `device.scan.armed` (armed_by_user_id, target_device_id, purpose, pairing_code_hash)
  - `device.scan.completed` (deviceId, idTagPrefix, success, latency_ms)
  - `device.scan.released` (deviceId, pairing_code_hash)
  - `device.token.issued` (deviceId, hashPrefix, ip)
  - `device.token.revoked` (deviceId, tokenId, reason)
  - `device.token.invalid` (hashPrefix, ip — for probe detection)
- **MED** Anomaly alerts:
  - Per-device scan rate >10/min → alert.
  - ≥5 401s on a single bearer token in 60s → revoke + alert.
  - Admin-initiated `device.scan.armed` against non-self device → alert at
    first occurrence.
  - APNs send failure rate >5% / 5min → page.

## Final non-negotiable checklist (single-glance)

The implementation team treats these as gating items:

1. Universal Links + PKCE (no custom URL scheme).
2. One-time code is single-use, atomic-claimed, hashed at rest.
3. `deviceToken` + `deviceSecret` returned only in register response body, with `Cache-Control: no-store`. Logger redacts.
4. `selectAuth(route)` is the single source of truth for auth scheme + origin exemption. Unit-tested rejection of bearer on admin routes.
5. Scan-result HMAC: `"scan-result/v1|"` prefix + 60s window + constant-time + atomic single-use claim.
6. SSE stream: per-device cap 1 with kick-off; per-IP cap 3; replay filter on `(deviceId, pairingCode)`.
7. Token revocation propagates via `device.token.revoked` event; SSE closes immediately on receipt.
8. Audit `device.scan.completed` with `idTagPrefix` only; no full UIDs in logs.
9. Phone scan-result NEVER routes through `/api/ocpp/pre-authorize`.
10. Phone holds enriched scan-result in-memory only; no persistent caching.
11. iOS Keychain: `deviceSecret` requires user presence (biometric); `deviceToken` is `AfterFirstUnlockThisDeviceOnly`.
12. Admin-arm on non-owned device: 403 in v1; gated owner-opt-in flow in v1.1.
