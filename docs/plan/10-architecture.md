# Architecture

## Domain model

### `devices` table (new)

Holds explicitly-registered devices (iPhones first, computers later). Chargers
stay in `chargers_cache` — they are NOT migrated.

```sql
CREATE TABLE devices (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  kind            TEXT NOT NULL CHECK (kind IN ('phone_nfc','laptop_nfc')),
  label           TEXT NOT NULL,                       -- user-supplied friendly name
  capabilities    TEXT[] NOT NULL DEFAULT ARRAY['tap'],
  owner_user_id   TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- iOS metadata
  platform        TEXT NOT NULL,                       -- 'ios' (extensible)
  model           TEXT NOT NULL,                       -- e.g. 'iPhone 16 Pro'
  os_version      TEXT NOT NULL,
  app_version     TEXT NOT NULL,
  -- Push delivery
  push_token      TEXT,
  apns_environment TEXT,                                -- 'sandbox' | 'production'
  -- Presence
  last_seen_at    TIMESTAMPTZ,
  last_status     JSONB,                                -- battery, network type, etc.
  -- Lifecycle
  registered_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at      TIMESTAMPTZ,                          -- soft-delete
  revoked_at      TIMESTAMPTZ,                          -- admin-forced
  revoked_by_user_id TEXT REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX idx_devices_owner_last_seen
  ON devices (owner_user_id, last_seen_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_devices_capabilities
  ON devices USING GIN (capabilities) WHERE deleted_at IS NULL;
```

### `device_tokens` table (new)

```sql
CREATE TABLE device_tokens (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id     UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  token_hash    TEXT NOT NULL UNIQUE,         -- SHA-256(raw token), hex
  secret_hash   TEXT NOT NULL,                -- SHA-256(deviceSecret), hex (for forensic verify)
  expires_at    TIMESTAMPTZ NOT NULL,
  revoked_at    TIMESTAMPTZ,
  last_used_at  TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_device_tokens_hash
  ON device_tokens (token_hash) WHERE revoked_at IS NULL;
```

The raw `deviceToken` and `deviceSecret` are returned **only once** in the
register endpoint response body. SHA-256 hashes are stored at rest. Verification
is constant-time hash compare.

### `tappable_devices` view (new)

```sql
CREATE VIEW tappable_devices AS
  SELECT
    charge_box_id          AS id,
    'charger'::text        AS kind,
    COALESCE(friendly_name, charge_box_id) AS label,
    ARRAY['ev','tap']::text[] AS capabilities,
    NULL::text             AS owner_user_id,
    first_seen_at          AS registered_at,
    last_seen_at,
    last_status,
    NULL::timestamptz      AS revoked_at
  FROM chargers_cache
UNION ALL
  SELECT
    id::text,
    kind,
    label,
    capabilities,
    owner_user_id,
    registered_at,
    last_seen_at,
    to_jsonb(last_status),
    revoked_at
  FROM devices
  WHERE deleted_at IS NULL;
```

Used by the new `/api/auth/scan-tap-targets` endpoint and the admin Devices page.

### Pairings reuse `verifications`

Existing `verifications` table holds the pairing rows. New identifier namespace:

```
device-scan:{deviceId}:{pairingCode}
```

Distinct from the existing `scan-pair:{chargeBoxId}:{pairingCode}` charger
pairings — no collision risk. 90-second TTL, atomic claim via
`UPDATE … WHERE status='armed' RETURNING` (mirrors `scan-login.ts:222` pattern).

## Auth model

### Login pathways (who can sign in, and how)

| User type | Pathway | Notes |
|---|---|---|
| Admin (web) | Pocket ID OIDC by default; email/password fallback when `ADMIN_AUTH_SHOW_FALLBACK=true` | If `ADMIN_OIDC_ISSUER` is unset, email/password is the only path |
| Admin (iOS app) | Same as web — the registration web view just renders whatever the admin login UI is | iOS app is **admin-only** — `POST /api/devices/register` rejects `role != 'admin'` with 403 |
| Customer (web) | Magic link OR scan-to-login on a charger | Unchanged from current behavior. No OIDC for customers. |
| Customer (iOS app) | NOT SUPPORTED | Customers do not register devices |

### Schemes (post-login, used by the API)

Two auth schemes coexist; routes accept exactly one.

| Scheme | Cookie session (BetterAuth `ev_billing_session`) | Bearer device token |
|---|---|---|
| Used by | Browser admin/customer | iOS app |
| CSRF | Origin header check | Token in Keychain unreachable from the web |
| Where parsed | `_middleware.ts` (existing) | `_middleware.ts` (new branch) |
| Issuance | BetterAuth (after OIDC or email/password) | `POST /api/devices/register` exchange |

### Cross-cutting middleware

The codebase already has these patterns; the device endpoints inherit them:

- **`src/lib/idempotency.ts`** — `withIdempotency(ctx, route, fn)` wrapper.
  All state-changing device endpoints opt in. See `20-contracts.md` §
  "Idempotency-Key support."
- **Magic-link timing-jitter** (`src/lib/auth.ts:144-156`) — 50-150ms latency
  floor masking user-exists vs. user-missing. Mirror in
  `POST /api/devices/register`.
- **CSP report-only header** (`_middleware.ts`) — already applied to all
  responses. No device-specific change needed.
- **Anti-enumeration error collapsing** (`scan-login.ts:247-256`) — pairing
  consumed/expired returns `429 rate_limited`, not `410 gone`, so attackers
  can't distinguish the two. Mirror in `/api/devices/scan-result`.

### OIDC integration (Pocket ID)

BetterAuth's generic-OIDC plugin is loaded only when `ADMIN_OIDC_ISSUER` is
set in env. Pocket ID acts as the issuer; on first OIDC login, a
just-in-time provisioning hook creates a `users` row with `role='admin'`
based on Pocket ID group claim membership (e.g. group `expressync-admins`).

The email/password plugin stays loaded unconditionally — it's the break-glass
path. `disableSignUp: true` is preserved; admins are still seeded via
`scripts/seed-admin.ts` for the bootstrap case.

**Single `selectAuth(route)` function** in `_middleware.ts` is the only source of
truth. Bearer routes are origin-exempt as a derived property. Routes:

| Route prefix | Scheme | Origin check |
|---|---|---|
| `/api/admin/*` | cookie only | yes |
| `/api/customer/*` | cookie only | yes |
| `/api/auth/*` | cookie or public | yes (writes) |
| `/api/devices/register` | cookie only | yes |
| `/api/devices/heartbeat`, `/scan-stream`, `/scan-result`, `/me`, `/{id}` (DELETE) | bearer only | exempt |
| `/api/ocpp/*` | HMAC (existing) | exempt (existing) |

Bearer accepting cookie OR cookie accepting bearer is **forbidden** (security
audit risk #11.1). Unit test asserts `/api/admin/*` rejects bearer.

## Scan delivery flow (sequence diagram)

```
 Web Portal       Backend                     Event Bus      APNs            iPhone
     │                │                           │            │                │
     ├─POST /admin/devices/{id}/scan-arm─────────>│            │                │
     │                │ INSERT verifications     │            │                │
     │                │  identifier='device-scan:{id}:{code}' │                │
     │                │ status='armed' ttl=90s   │            │                │
     │                ├─publish device.scan.requested────────>│ (SSE worker)   │
     │                │                           │            ├─SSE event────>│
     │                ├─apns.send (async, no await)──────────>│                │
     │<─200 {pairingCode, expiresInSec}──────────│            │                │
     │                │                           │            ├─push (if bgd)>│ (dedup by
     │                │                           │            │                │  pairingCode)
     │                │                           │            │                │
     │                │                           │            │   [user taps card with iPhone]
     │                │                           │            │                │
     │                │<─POST /api/devices/scan-result─────────────────────────│
     │                │  { idTag, pairingCode, ts, nonce }    │                │
     │                │  Authorization: Bearer dev_...        │                │
     │                │ verify HMAC, atomic claim, lookup     │                │
     │                ├─publish scan.intercepted──>│            │                │
     │                │   { idTag, pairableType:  │            │                │
     │                │   'device', pairableId,   │            │                │
     │                │   pairingCode, t }        │            │                │
     │<─SSE scan.intercepted─────────────────────│            │                │
     │                │                           │            │                │
     │                │<─200 { found, tag: enriched }──────────────────────────│
     │                │                           │            │   [iPhone shows
     │ (modal updates with customer info)         │            │    customer card]
```

The crucial property: the existing `scan.intercepted` event is reused, so the
website's scan modal sees no behavioral difference between charger-sourced and
device-sourced scans.

## Realtime infrastructure (delivery layer)

- **SSE** on `GET /api/devices/scan-stream` — bearer auth, persistent while
  foregrounded. Server filters events by `payload.deviceId === ctx.state.device.id`.
  `Last-Event-ID` resume from event-bus 60s replay buffer.
- **APNs** on a fire-and-forget basis from the arm handler (no `await`).
  Visible push, `apns-priority: 10`, `apns-push-type: alert`,
  `interruption-level: time-sensitive`, `apns-collapse-id: scan-{pairingCode}`,
  `apns-expiration: <pairing-expires-at-epoch>`.
- **Coalescing on device:** keep `processedPairingCodes: [pairingCode → Date]`
  in app memory + `UserDefaults` mirror; entries expire 90s after seen. Any
  duplicate `pairingCode` (push or SSE) is silently dropped.
- **Stream cap:** 1 active stream per `device_id`. New connection emits
  `device.session.replaced` to the old stream and closes it.

## Threat model summary

(See [`60-security.md`](60-security.md) for the full checklist.)

The scan-arm flow already establishes a strong threat model in the existing
charger system; the iPhone path inherits it with two added concerns:

1. **Token issuance is new attack surface.** Mitigated by Universal Links +
   PKCE, atomic single-use code claim, and showing token/secret only once in
   the registration response body (never in URL/redirect).
2. **Admin force-arming a customer's phone** without consent is a novel risk.
   Mitigated by: owner-self-arm by default, an `admin_arm_allowed` opt-in in
   device settings, visible push with requester identity for cross-user arms,
   and audit log alerting at first occurrence.

The existing patterns (HMAC nonce with replay window, atomic single-use claim
on `verifications`, generic error messages, role guards, audit-first writes)
all carry over. The phone path uses **per-device `deviceSecret`** (HMAC key)
rather than the global `AUTH_SECRET` — domain separation.
