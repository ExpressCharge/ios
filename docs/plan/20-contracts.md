# Canonical Contracts

This is the **single source of truth** for cross-track contracts. All three
implementation tracks (backend, frontend, iOS) MUST conform to these shapes.
Changes here require sign-off from all three tracks.

## TypeScript types (shared)

To live in `expresscharge/src/lib/types/devices.ts`, mirrored as Swift `Codable`
structs in `expresscan/Sources/Models/`.

```ts
export const DEVICE_KINDS = ["phone_nfc", "laptop_nfc"] as const;
export type DeviceKind = typeof DEVICE_KINDS[number];

export const DEVICE_CAPABILITIES = ["tap", "ev"] as const;
export type DeviceCapability = typeof DEVICE_CAPABILITIES[number];

export const SCAN_PURPOSES = [
  "admin-link",     // admin scanning to link a tag to a customer
  "customer-link",  // customer adding a card to their account
  "login",          // scan-to-login flow
  "view-card",      // admin or customer looking up a card
] as const;
export type ScanPurpose = typeof SCAN_PURPOSES[number];

export interface DeviceSummary {
  deviceId: string;
  kind: DeviceKind;
  label: string;
  capabilities: DeviceCapability[];
  ownerUserId: string | null;     // null for chargers
  platform: string | null;
  model: string | null;
  appVersion: string | null;
  lastSeenAtIso: string | null;
  isOnline: boolean;
  registeredAtIso: string;
}

export interface TapTargetEntry {
  deviceId: string;                    // for phones: UUID; for chargers: chargeBoxId
  pairableType: "device" | "charger";
  kind: "charger" | "phone_nfc" | "laptop_nfc";
  label: string;
  capabilities: DeviceCapability[];
  isOnline: boolean;
  isOwnDevice?: boolean;               // hint to frontend for picker grouping
}

/** Returned from POST /api/devices/scan-result */
export interface EnrichedScanResult {
  ok: true;
  found: boolean;
  pairingCode: string;
  idTag: string;                       // hex uppercase
  resolvedAtIso: string;
  tag: {
    displayName: string | null;
    tagType: string;                   // "ev_card", "phone_nfc", etc.
  } | null;
  customer: {
    displayName: string | null;        // first non-null of: customerName, slug, externalId
    slug: string | null;
  } | null;
  subscription: {
    planLabel: string | null;          // first non-null of: subscriptionName, planCode
    status: "active" | "pending" | "terminated" | "canceled" | null;
    currentPeriodEndIso: string | null;
    billingTier: "standard" | "comped" | null;
  } | null;
}

/** Sent in DEVICE.SCAN.REQUESTED event and APNs payload */
export interface DeviceScanRequestedPayload {
  deviceId: string;
  pairingCode: string;
  purpose: ScanPurpose;
  expiresAtIso: string;
  expiresAtEpochMs: number;
  requestedByUserId: string | null;    // null = system-initiated
  hintLabel: string | null;            // free-text shown in app, e.g. "Front desk"
}
```

## Database additions

See [`10-architecture.md`](10-architecture.md) for the full DDL of `devices`,
`device_tokens`, and the `tappable_devices` view. New audit event types:

```
device.registered
device.deregistered
device.scan.armed
device.scan.completed
device.scan.released
device.token.issued
device.token.revoked
device.token.invalid       (failed bearer auth — for probe detection)
```

## Event bus additions

Adds to `EventBusEventType` in `src/services/event-bus.service.ts`:

| Type | Payload | Filter on subscribe |
|---|---|---|
| `device.scan.requested` | `DeviceScanRequestedPayload` | `payload.deviceId === ctx.state.device.id` |
| `device.scan.completed` | `{ deviceId, pairingCode, idTag, t, success }` | `payload.deviceId === ctx.state.device.id` |
| `device.session.replaced` | `{ deviceId, replacedAt }` | `payload.deviceId === ctx.state.device.id` |
| `device.token.revoked` | `{ deviceId, tokenId }` | `payload.deviceId === ctx.state.device.id` |

The existing **`scan.intercepted`** event is generalized so the filter is
`(pairableType, pairableId, pairingCode)`. The legacy `chargeBoxId` field is
removed — all consumers are updated as part of this work.

```ts
export interface ScanInterceptedPayload {
  idTag: string;
  pairableType: "charger" | "device";
  pairableId: string;                  // chargeBoxId (when type=charger) or deviceId
  pairingCode: string;
  purpose: ScanPurpose;
  t: number;                            // ms epoch
  source: "ocpp-preauth" | "device-scan-result";
}
```

## HTTP endpoints

### Device lifecycle

| # | Method | Path | Auth | Purpose |
|---|---|---|---|---|
| 1 | POST | `/api/devices/register` | Cookie + PKCE verifier | Issue device + bearer token + secret |
| 2 | POST | `/api/devices/heartbeat` | Bearer | Bump `last_seen_at` |
| 3 | DELETE | `/api/devices/{deviceId}` | Bearer (own device) | Self-deregister |
| 4 | PUT | `/api/devices/{deviceId}/push-token` | Bearer (own device) | Update APNs token + environment |
| 5 | GET | `/api/devices/me` | Bearer | Identity sanity check |

### Admin device management

| # | Method | Path | Auth | Purpose |
|---|---|---|---|---|
| 6 | GET | `/api/admin/devices` | Admin cookie | List devices with filters |
| 7 | GET | `/api/admin/devices/{deviceId}` | Admin cookie | Detail |
| 8 | POST | `/api/admin/devices/{deviceId}/deregister` | Admin cookie | Force-revoke |
| 9 | POST | `/api/admin/devices/{deviceId}/rename` | Admin cookie | Update label |

### Scan triggering

| # | Method | Path | Auth | Purpose |
|---|---|---|---|---|
| 10 | POST | `/api/admin/devices/{deviceId}/scan-arm` | Admin cookie or owner cookie | Arm a scan; publish event + push |
| 11 | DELETE | `/api/admin/devices/{deviceId}/scan-arm` | Admin cookie or owner cookie | Release |
| 12 | GET | `/api/devices/scan-stream` | Bearer | SSE stream of scan requests |
| 13 | POST | `/api/devices/scan-result` | Bearer | Phone reports UID, returns enriched result |
| 14 | GET | `/api/devices/scan-result/{pairingCode}` | Bearer | Polling fallback for enriched result |
| 15 | GET | `/api/auth/scan-tap-targets` | Cookie | List tap-capable targets (chargers + phones) |

### Web-side scan-detect (generalized)

The existing `/api/auth/scan-detect` is **generalized** to accept either
`chargeBoxId` or `deviceId` (one is required). It checks the appropriate
identifier namespace (`scan-pair:` vs `device-scan:`) and the same
`scan.intercepted` event filter handles both. No sibling endpoint.

```
GET /api/auth/scan-detect?pairingCode=…&chargeBoxId=… (charger flow)
GET /api/auth/scan-detect?pairingCode=…&deviceId=…    (device flow)
```

Internally one handler, branches on which query param is set.

## Endpoint detail: POST /api/devices/register

```
POST /api/devices/register
Cookie: ev_billing_session=…
Content-Type: application/json

{
  "oneTimeCode": "abc123…",            // from Universal Link callback, ≤60s old
  "codeVerifier": "…",                  // PKCE verifier (matches challenge sent to web)
  "label": "Aisha's iPhone",
  "platform": "ios",
  "model": "iPhone 16 Pro",
  "osVersion": "18.4.1",
  "appVersion": "1.0.0",
  "pushToken": "<base64>",
  "apnsEnvironment": "sandbox" | "production",
  "requestedCapabilities": ["tap"]
}

→ 200 { ok, deviceId, deviceToken, deviceSecret, capabilities, expiresAtIso }
   (response NEVER cached: Cache-Control: no-store, Pragma: no-cache)

→ 400 { error: "invalid_code" | "invalid_verifier" | "invalid_platform" | "invalid_capabilities" }
→ 401 { error: "unauthorized" }
→ 410 { error: "code_expired" }
→ 429 { error: "rate_limited" }
```

`deviceToken` format: `dev_<32 random bytes base64url>` (the literal `dev_` prefix is required for middleware detection).
`deviceSecret`: 32 random bytes base64url-encoded. Used for HMAC nonces.

## Endpoint detail: POST /api/devices/scan-result

```
POST /api/devices/scan-result
Authorization: Bearer dev_…
Content-Type: application/json

{
  "idTag": "04AB12CDEF1234",            // hex uppercase
  "pairingCode": "X7R2KQ",
  "ts": 1745622000,                      // unix seconds, ±60s of server clock
  "nonce": "a3f9…"                        // hex HMAC-SHA256
}
```

The `nonce` is computed as:

```
nonce = HMAC-SHA256(
  key = deviceSecret (raw, base64url-decoded),
  msg = "scan-result/v1|" + idTag + "|" + pairingCode + "|" + deviceId + "|" + ts
)
```

The `"scan-result/v1|"` prefix is **required** for domain separation (security
audit recommendation 6.1). The `deviceSecret` MUST NOT be reused for any other
HMAC purpose; if needed, derive subkeys with HKDF.

Server-side processing:

1. Bearer middleware → `ctx.state.device`.
2. Validate `ts` within ±60s.
3. Recompute HMAC, constant-time compare with `nonce`. Mismatch → 401.
4. Atomic UPDATE `verifications` SET status='consumed', matchedIdTag=idTag
   WHERE identifier='device-scan:{deviceId}:{pairingCode}' AND status='armed'
   AND expires_at > now() RETURNING …. Zero rows → 410.
5. Publish `scan.intercepted` event with `pairableType: 'device'`,
   `pairableId: deviceId`, `source: 'device-scan-result'`.
6. Look up enriched info via `user_mappings` JOIN customer + subscription cache.
7. Audit log `device.scan.completed` with `idTagPrefix: idTag.slice(0,4)` only
   (never full UID — matches existing `scan-login.ts:293` pattern).
8. Return `EnrichedScanResult` with `found: true|false`.

```
→ 200 EnrichedScanResult
→ 400 { error: "clock_skew" | "invalid_body" }
→ 401 { error: "unauthorized" | "invalid_nonce" }
→ 429 { error: "rate_limited" }   ← also returned for pairing_consumed / pairing_expired
                                     to match the anti-enumeration pattern in
                                     `scan-login.ts:247-256` (don't let an
                                     attacker distinguish "real pairing just
                                     got consumed" from "throttled")
```

## Endpoint detail: GET /api/devices/scan-stream (SSE)

```
GET /api/devices/scan-stream
Authorization: Bearer dev_…
Last-Event-ID: 1234           (optional)

→ 200 text/event-stream
   : keepalive             (every 15s; bumps last_seen_at every 4th tick)

   event: connected
   id: 1
   data: {"deviceId":"…","scanStreamVersion":1}

   event: scan.requested
   id: 1235
   data: {"deviceId":"…","pairingCode":"X7R2KQ","purpose":"admin-link",
          "expiresAtIso":"…","expiresAtEpochMs":…,
          "requestedByUserId":"alice","hintLabel":"Front desk"}

   event: device.session.replaced       (this stream is being replaced)
   data: {}

   event: device.token.revoked          (token revoked → close)
   data: {}

→ 401 (not text/event-stream — JSON 401 before upgrading)
→ 410 (device deleted)
```

Concurrency: **1 stream per deviceId**, kick-off semantics. New connect →
`device.session.replaced` to the old stream, then close. Per-IP cap: 3 streams
(matches existing `MAX_CONCURRENT_PER_IP = 3` in `scan-detect.ts:43`).

## APNs payload (canonical)

```json
{
  "aps": {
    "alert": { "title": "Scan a card now", "body": "Tap to start the NFC scan" },
    "sound": "default",
    "category": "NFC_SCAN_REQUEST",
    "thread-id": "device-scan-<deviceId>",
    "interruption-level": "time-sensitive",
    "mutable-content": 1
  },
  "v": 1,
  "deviceId": "uuid",
  "pairingCode": "X7R2KQ",
  "purpose": "admin-link",
  "hintLabel": "Front desk",
  "expiresAtEpochMs": 1745622090000
}
```

Headers: `apns-push-type: alert`, `apns-priority: 10`,
`apns-expiration: <pairing-expires unix-seconds>`,
`apns-collapse-id: scan-<pairingCode>`,
`apns-topic: <bundle-id>`.

The `pairingCode` in the payload is treated as a target identifier, not a
secret — it is single-use and 90s-TTL'd, and acting on it requires the bearer
token + deviceSecret which are not in the push payload.

## Idempotency-Key support

All state-changing device endpoints support the existing `Idempotency-Key`
request header pattern via `src/lib/idempotency.ts`'s
`withIdempotency(ctx, route, fn)` wrapper. Apply to:

- `POST /api/devices/register`
- `POST /api/devices/heartbeat` (cheap; optional)
- `DELETE /api/devices/{deviceId}`
- `POST /api/devices/{deviceId}/push-token`
- `POST /api/devices/scan-result`
- `POST /api/admin/devices/{deviceId}/scan-arm`
- `DELETE /api/admin/devices/{deviceId}/scan-arm`
- `POST /api/admin/devices/{deviceId}/deregister`
- `POST /api/admin/devices/{deviceId}/rename`

Behavior is unchanged from existing usage: keys are scoped per (key, route,
userId) and replays return the cached status+body for 24h. The iOS app SHOULD
generate a UUID per write request and send it in `Idempotency-Key` so a
network-blip retry doesn't double-arm or double-register.

## Rate-limit buckets (additions)

| Bucket | Cap | Routes |
|---|---|---|
| `device-register:{ip}` | 5/min | `POST /api/devices/register` |
| `device:{deviceId}` | 120/min | All `/api/devices/*` bearer routes combined |
| `device-scan-stream:{deviceId}` | concurrency 1 (kick-off) | SSE stream |
| `device-scan-stream:{ip}` | concurrency 3 | SSE stream (per-IP cap matches existing pattern) |
| `device-scan-arm:{deviceId}` | 10/min | Per-device arm cap (anomaly threshold) |

## Cookies (no changes)

`ev_billing_session` cookie behavior is unchanged. The iOS app's
ASWebAuthenticationSession opens the existing web login; cookies are isolated
to the auth-session sandbox and discarded after the universal-link callback
fires. The iOS app does not store, send, or read cookies post-registration.
