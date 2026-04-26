# Backend Implementation Plan (`expresscharge`)

All work is in `/Users/scruffy/Documents/Repos/expresscharge`. Tech: Fresh +
Deno + Drizzle + Postgres + BetterAuth.

## Pocket ID OIDC integration

Add a generic-OIDC plugin to BetterAuth, gated by env vars. Pocket ID becomes
the daily-driver login for admins; email/password stays as a break-glass.

### Env vars (add to `src/lib/config.ts`)

```
# OIDC (when unset, falls back to email/password only)
ADMIN_OIDC_ISSUER             # https://pocket-id.example.com
ADMIN_OIDC_CLIENT_ID
ADMIN_OIDC_CLIENT_SECRET
ADMIN_OIDC_ADMIN_GROUP        # e.g. "expresscharge-admins" — Pocket ID group claim that grants role='admin'
ADMIN_AUTH_SHOW_FALLBACK      # "true" to show email/password link below the OIDC button; default unset
```

Note the existing `STEVE_PREAUTH_HMAC_KEY` is now unconditional (commit
`8690576` removed `FEATURE_PAIR_INTENT_INTERCEPT`). The route returns 401
when the key is empty so a misconfigured deploy is loudly broken — the same
pattern applies to OIDC config: empty issuer means OIDC isn't enabled, but no
silent 503s.

A sibling secret `STEVE_METERVALUE_HMAC_KEY` (with fallback to
`STEVE_PREAUTH_HMAC_KEY`) was added for the new `/api/ocpp/meter-values` hook.
Not used by ExpresScan; documented here so future env-var changes don't
inadvertently break either.

### Login UI logic (`routes/login.tsx`)

Server-side branch on env config:

```
if (!ADMIN_OIDC_ISSUER):
    render <EmailPasswordForm /> only (current behavior)
elif !ADMIN_AUTH_SHOW_FALLBACK:
    server-side 302 to BetterAuth's OIDC start endpoint
    (no form rendered — direct redirect)
else:
    render <OIDCButton primary /> + small text link "Sign in with email instead" → reveals/navigates to /login/email
```

### JIT provisioning on first OIDC login

BetterAuth's `databaseHooks` callback for user creation:
- If user originated from OIDC (`account.providerId === 'pocket-id'`):
  - Inspect ID token's `groups` claim.
  - If contains `ADMIN_OIDC_ADMIN_GROUP`: set `role = 'admin'`.
  - Otherwise: reject (error: not authorized — admin-only IdP path).
- Email/password path keeps the existing seed-script flow.

### Files to create

```
src/lib/auth-oidc.ts                          # generic-OIDC plugin config + JIT hook
routes/login/email.tsx                         # the email/password form (split out from /login)
```

### Files to modify

```
src/lib/auth.ts                                # conditionally load generic-OIDC plugin
routes/login.tsx                               # 3-mode branching login UI
src/lib/config.ts                              # OIDC env vars
.env.example                                   # document new env vars
```

## Files to create

```
src/db/schema.ts                              # add `devices`, `deviceTokens` tables
src/lib/types/devices.ts                      # shared TypeScript types
src/lib/devices/auth.ts                       # bearer token verify, HMAC compute/verify
src/lib/devices/registration.ts               # one-time-code + PKCE management
                                              # use withIdempotency() from src/lib/idempotency.ts
src/lib/apns.ts                               # APNs HTTP/2 client + JWT signer
src/services/device-presence.service.ts       # last_seen bump, online check
src/services/device-enrichment.service.ts     # tag lookup → EnrichedScanResult

drizzle/0032_devices_and_tokens.sql           # the migration
drizzle/0033_tappable_devices_view.sql        # the view

routes/api/devices/register.ts                # POST register
routes/api/devices/heartbeat.ts               # POST heartbeat
routes/api/devices/me.ts                      # GET me
routes/api/devices/[deviceId].ts              # DELETE
routes/api/devices/[deviceId]/push-token.ts   # PUT push-token
routes/api/devices/scan-stream.ts             # GET SSE
routes/api/devices/scan-result.ts             # POST scan-result
routes/api/devices/scan-result/[pairingCode].ts # GET polling fallback
routes/api/devices/scan-detect.ts             # GET browser-side SSE for device-armed scans

routes/api/admin/devices/index.ts             # GET list
routes/api/admin/devices/[deviceId].ts        # GET detail
routes/api/admin/devices/[deviceId]/deregister.ts  # POST
routes/api/admin/devices/[deviceId]/rename.ts # POST
routes/api/admin/devices/[deviceId]/scan-arm.ts # POST + DELETE

routes/api/auth/scan-tap-targets.ts           # GET unified picker (replaces scan-charger-list outright)

routes/.well-known/apple-app-site-association.json # Universal Links manifest
```

## Files to modify

```
src/db/schema.ts                              # add tables (above)
src/services/event-bus.service.ts             # add new event types
src/lib/audit.ts                              # add new audit event types
src/lib/config.ts                             # APNs env vars
src/lib/origin.ts                             # ensure assertSameOrigin is called only on cookie routes
routes/_middleware.ts                         # add bearer-auth branch + selectAuth function
routes/api/auth/scan-detect.ts                # generalize event filter to (pairableId, pairingCode)
                                              # accept either chargeBoxId or deviceId param

# DELETE — replaced by scan-tap-targets
routes/api/auth/scan-charger-list.ts          # delete file; rename callers
```

## Admin-only enforcement on devices

Mirror migration 0018's role-trigger pattern (which enforced
`user_mappings.user_id` → customer-only) for `devices.owner_user_id` →
admin-only:

```sql
-- In drizzle/0032_devices_and_tokens.sql, after CREATE TABLE devices:

CREATE OR REPLACE FUNCTION devices_owner_must_be_admin()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.owner_user_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM users WHERE id = NEW.owner_user_id AND role = 'admin'
    ) THEN
      RAISE EXCEPTION 'devices.owner_user_id must reference a user with role=admin (got %)',
        NEW.owner_user_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER devices_owner_must_be_admin_trg
  BEFORE INSERT OR UPDATE ON devices
  FOR EACH ROW EXECUTE FUNCTION devices_owner_must_be_admin();
```

`POST /api/devices/register` MUST also check `ctx.state.user.role === 'admin'`
in app code and return `403 forbidden` for customer sessions BEFORE attempting
the insert (so we get a clean error message, not a constraint violation).

## Migration: `drizzle/0032_devices_and_tokens.sql`

```sql
-- New tables for the iPhone (and future) NFC reader devices.
-- Chargers continue to live in `chargers_cache`; this table is additive.

CREATE TABLE devices (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  kind            TEXT NOT NULL CHECK (kind IN ('phone_nfc','laptop_nfc')),
  label           TEXT NOT NULL,
  capabilities    TEXT[] NOT NULL DEFAULT ARRAY['tap'],
  owner_user_id   TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform        TEXT NOT NULL,
  model           TEXT NOT NULL,
  os_version      TEXT NOT NULL,
  app_version     TEXT NOT NULL,
  push_token      TEXT,
  apns_environment TEXT CHECK (apns_environment IN ('sandbox','production')),
  last_seen_at    TIMESTAMPTZ,
  last_status     JSONB,
  registered_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at      TIMESTAMPTZ,
  revoked_at      TIMESTAMPTZ,
  revoked_by_user_id TEXT REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX idx_devices_owner_last_seen
  ON devices (owner_user_id, last_seen_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_devices_capabilities
  ON devices USING GIN (capabilities) WHERE deleted_at IS NULL;
CREATE INDEX idx_devices_last_seen
  ON devices (last_seen_at DESC) WHERE deleted_at IS NULL;

CREATE TABLE device_tokens (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id     UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  token_hash    TEXT NOT NULL UNIQUE,
  secret_hash   TEXT NOT NULL,
  expires_at    TIMESTAMPTZ NOT NULL,
  revoked_at    TIMESTAMPTZ,
  last_used_at  TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_device_tokens_hash
  ON device_tokens (token_hash) WHERE revoked_at IS NULL;
CREATE INDEX idx_device_tokens_device
  ON device_tokens (device_id, created_at DESC);
```

## Migration: `drizzle/0033_tappable_devices_view.sql`

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
    NULL::timestamptz      AS deleted_at,
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
    deleted_at,
    revoked_at
  FROM devices
  WHERE deleted_at IS NULL;
```

## Idempotency wrapper for state-changing endpoints

The codebase already has `src/lib/idempotency.ts` providing
`withIdempotency(ctx, route, fn)`. All state-changing device endpoints MUST
opt in. Per-route call sites:

```ts
// Example for /api/devices/register
export const handler = define.handlers({
  async POST(ctx) {
    return withIdempotency(ctx, "/api/devices/register", async () => {
      // existing handler body
    });
  },
});
```

Apply this wrapper to: `register`, `heartbeat` (optional), `scan-result`,
admin `scan-arm` (POST + DELETE), admin `deregister`, admin `rename`,
device `DELETE /api/devices/{id}`, device `PUT /api/devices/{id}/push-token`.

Why: a network blip causing the iOS app to retry POST `/api/devices/register`
must not produce two `devices` rows. The header is opt-in; iOS sends a UUID
per write, the backend caches the response for 24h.

## Latency-floor on register

Mirror the magic-link timing-jitter pattern (`auth.ts:144-156`) on
`POST /api/devices/register`: a 50-150ms `Promise.race`-ish floor that masks
the difference between "valid one-time code, expensive INSERT" and "invalid
code, fast 401." Code reference: see the `jitter`/`jitterPromise` block in
`src/lib/auth.ts` magic-link `sendMagicLink`.

## `_middleware.ts` changes (the most security-sensitive change)

Add a `selectAuth(pathname): "bearer" | "cookie" | "public" | "ocpp-hmac"`
function. Single source of truth for both auth scheme AND origin-exemption.

```ts
function selectAuth(pathname: string): AuthScheme {
  if (pathname.startsWith("/api/ocpp/")) return "ocpp-hmac";
  if (pathname === "/api/devices/register") return "cookie";
  if (pathname.startsWith("/api/devices/")) return "bearer";
  if (pathname.startsWith("/api/admin/")) return "cookie";
  if (pathname.startsWith("/api/customer/")) return "cookie";
  return "public-or-cookie";
}
```

Then:

```ts
const scheme = selectAuth(pathname);

if (scheme === "bearer") {
  const ctxDevice = await resolveBearer(req);
  if (!ctxDevice) return jsonResponse(401, { error: "unauthorized" });
  ctx.state.device = ctxDevice;
  // Origin check skipped (bearer is CSRF-immune; mobile clients don't send Origin)
} else if (scheme === "cookie") {
  // existing cookie session resolution
  // assertSameOrigin on writes (existing behavior)
} else if (scheme === "ocpp-hmac") {
  // existing pre-authorize HMAC check (no change)
}
```

**Critical:** `/api/admin/*` MUST reject bearer-auth requests (return 401 if
`ctx.state.device` is set but `ctx.state.user` is not). Add a unit test.

## Bearer middleware specifics

```
function resolveBearer(req): Promise<DeviceContext | null> {
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer dev_")) return null;
  const raw = auth.slice("Bearer ".length);
  const hash = sha256Hex(raw);
  const row = await db
    .select(...)
    .from(deviceTokens)
    .innerJoin(devices, eq(deviceTokens.deviceId, devices.id))
    .where(and(
      eq(deviceTokens.tokenHash, hash),
      isNull(deviceTokens.revokedAt),
      gt(deviceTokens.expiresAt, sql`now()`),
      isNull(devices.deletedAt),
    ))
    .limit(1);
  if (!row) {
    void logAudit("device.token.invalid", { ip, ua, hashPrefix: hash.slice(0,8) });
    return null;
  }
  // bump last_used_at non-blocking (fire and forget update)
  void db.update(deviceTokens).set({ lastUsedAt: sql`now()` }).where(eq(deviceTokens.id, row.tokenId));
  return {
    id: row.deviceId,
    ownerUserId: row.ownerUserId,
    capabilities: row.capabilities,
    secretHash: row.secretHash,
  };
}
```

## APNs client

`src/lib/apns.ts` — token-based JWT auth (ES256), HTTP/2 to `api.push.apple.com`
or `api.sandbox.push.apple.com` based on the device's `apns_environment` column.

Required env vars (add to `src/lib/config.ts`):

```
APNS_KEY_ID            # 10-char Apple-issued key ID
APNS_TEAM_ID           # 10-char Apple Team ID
APNS_KEY_BASE64        # base64-encoded P8 private key
APNS_TOPIC             # bundle ID, e.g. "gg.vlad.expresscan"
```

JWTs signed once per worker, cached for ~50min (Apple requires <60min freshness).
Send is fire-and-forget from the arm handler; failures logged + metered.

## Universal Links manifest

`routes/.well-known/apple-app-site-association.json`:

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appIDs": ["ABC1234XYZ.gg.vlad.expresscan"],
        "components": [
          { "/": "/expresscan/register/*" }
        ]
      }
    ]
  }
}
```

Served with `Content-Type: application/json` (no `.json` extension required by
iOS, but harmless). Apple fetches this from the registered domain to validate
the app's claim on the URL pattern.

## Registration flow (PKCE)

1. iOS app generates `codeVerifier` (random 32 bytes, base64url) and
   `codeChallenge = SHA256(codeVerifier)` (base64url).
2. iOS opens `ASWebAuthenticationSession` to
   `https://manage.example.com/expresscan/register?codeChallenge={…}&label={…}`.
   The web view requires the user's existing cookie session.
3. User logs in via the existing flow.
4. Backend's `/expresscan/register` page generates a `oneTimeCode` (32-byte
   base64url), inserts into `verifications` with identifier
   `expresscan-register:{userId}:{hashedCode}`, value `{codeChallenge, …}`,
   60s TTL.
5. Page redirects to `https://manage.example.com/expresscan/register/callback?code={oneTimeCode}` — Universal Link.
6. iOS receives the Universal Link, extracts `code`, sends
   `POST /api/devices/register` with `{oneTimeCode, codeVerifier, ...registration data}`.
7. Backend verifies `SHA256(codeVerifier) === stored codeChallenge`, atomically
   claims the verification row, creates `devices` and `device_tokens` rows,
   returns `{deviceToken, deviceSecret, deviceId, capabilities, expiresAtIso}`.
8. The verification row's status flips to `consumed`.

## Test plan

### Unit
- Bearer middleware: valid token, revoked token, deleted device, malformed header.
- HMAC compute/verify: known vectors, constant-time compare.
- Atomic pairing claim: two concurrent calls, one wins.
- APNs JWT signer: known vector test.
- Registration: PKCE verifier mismatch, expired code, replay (already consumed).

### Integration (`tests/integration/devices/`)
- Full register flow with mock cookie session.
- `selectAuth` rejection: bearer on `/api/admin/devices` returns 401.
- Heartbeat updates `last_seen_at`.
- SSE stream: connect, receive arm event, kick-off on second connect.
- scan-result: success path, HMAC mismatch, expired pairing, replay window.
- `tappable_devices` view returns chargers + phones with correct shapes.
- `scan.intercepted` event fires with both legacy `chargeBoxId` field (for
  charger source) and new `pairableId`/`pairableType` fields.

### Performance
- Bearer middleware adds <2ms p95 to authenticated request latency.
- SSE supports ≥500 concurrent streams per worker without issue.
