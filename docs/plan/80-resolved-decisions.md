# Resolved Design Decisions

Decisions where the parallel design agents disagreed, plus how they were
resolved. Captured here so future contributors can see the reasoning, not just
the conclusion.

## 1. Custom URL scheme vs Universal Links for registration callback

**Conflict:** iOS architect proposed `expresscan-callback://register`. Security
audit flagged this as a hijack risk (any other app can register the same
scheme).

**Resolved:** **Universal Links** (`https://manage.polaris.express/expresscan/register/callback`)
+ **PKCE** (codeVerifier + codeChallenge in the registration handshake).
Universal Links bind the URL to our App ID via the
`apple-app-site-association` manifest, which iOS validates before opening the
app. PKCE binds the code redemption to the same app instance that initiated
the flow, defeating intercept-and-redeem attacks.

## 2. Auto-dismiss the Success screen after 5s?

**Conflict:** iOS architect + UX wireframes spec'd a 5s auto-return. Apple HIG
expert + UX researcher recommended manual dismissal.

**Resolved:** **Manual dismiss only.** Auto-dismiss feels marketing-y and
breaks accessibility (VoiceOver users may not finish reading). Future option:
opt-in setting after the user has seen N successful scans.

## 3. NFC polling options

**Conflict:** iOS architect spec'd `[.iso14443]` only. Apple HIG expert
recommended adding `.iso15693`.

**Resolved:** Use `[.iso14443, .iso15693]`. Some legacy EV access systems use
ISO 15693 vicinity tags; supporting it is free.

## 4. `BGAppRefreshTask` for backgrounded heartbeat

**Conflict:** iOS architect included it. Apple HIG expert recommended dropping
it.

**Resolved:** **Drop it.** Fires unpredictably on Apple's schedule, marginal
value, battery cost. The 120s online threshold absorbs one missed beat;
backgrounded phones go offline by design (which is accurate — push is the
recovery channel).

## 5. Reuse `/api/ocpp/pre-authorize` for phone scan-result?

**Conflict:** Original brief asked "ideally same endpoint." Architect, backend
engineer, and security audit all said no.

**Resolved:** **New sibling endpoint `POST /api/devices/scan-result`.** The
pre-authorize endpoint has a SteVe-bound HMAC contract, expects a different
body shape, and is service-to-service exempt from auth/origin/rate-limit. Phone
is user-to-service with bearer auth. Mixing them weakens both threat models.
Both paths publish the **same** `scan.intercepted` event, so the website's
scan modal sees uniform behavior.

## 6. Sign-out vs deregister (iOS)

**Conflict:** Settings could have separate "Sign out" (clear local) and
"Deregister" (also remove from backend) actions.

**Resolved:** **Unify them.** Sign-out always deregisters. Reasoning: a
signed-out-but-still-registered device is a phantom — admins see it in the
picker, scans target a phone that won't act. Single action matches user mental
model ("I'm leaving, I'm gone").

## 7. SSE concurrent stream cap per device

**Conflict:** Backend engineer suggested 5 streams per device. Realtime
engineer recommended 1 with kick-off.

**Resolved:** **1 stream per device, kick-off semantics.** New connection
emits `device.session.replaced` to the old stream and closes it. A second
concurrent stream almost certainly indicates a stale TCP connection on a dead
worker; the new stream is authoritative.

## 8. Bearer auth on admin routes (defense in depth)?

**Conflict:** Implicit assumption it's harmless to let bearer tokens
authenticate on admin routes (they'll just be unauthorized by role).

**Resolved:** **Hard reject** — `/api/admin/*` returns 401 if `ctx.state.device`
is set. Single `selectAuth(route)` function is the only source of truth for
which scheme is accepted AND whether origin is enforced. Avoids the
"bearer + cookie" CSRF confusion class of bug.

## 9. Pairing TTL, replay window, online threshold

**Conflict:** Different agents used different numbers (60s, 90s, 120s, 180s).

**Resolved:** Three distinct values, each with its own role:
- **Pairing TTL: 90s** (matches existing `scan-pair`).
- **HMAC replay window: 60s** (matches existing `scan-login`).
- **Phone online threshold: 120s** (2× heartbeat interval).
- **Charger online threshold: 60min** (existing, unchanged).

## 10. Frontend feature flag `FEATURE_DEVICES_GENERIC_TAP`

**Conflict:** Original frontend doc gated the picker swap behind a flag.

**Resolved:** **No flag.** The system isn't live yet, so we rename
`/api/auth/scan-charger-list` → `/api/auth/scan-tap-targets` outright and
update all callers in the same release. Avoids carrying dual code paths.

## 11. Admin scanning on a customer's phone (not applicable)

**Conflict:** Original threat model assumed customer phones could be scan
targets that admins might force-arm.

**Resolved:** **Not applicable.** iOS app is admin-only. Customers don't
register devices. The cross-arming risk reduces to "admin A arms a scan on
admin B's phone" — addressed in v1 by simply only allowing owner-self-arm
(picker hides phones not owned by the current admin); admin-cross-arm with
owner consent is deferred to v1.1.

## 12. OIDC for customers?

**Conflict:** Easy to over-extend "Pocket ID for everything."

**Resolved:** **Pocket ID is admin-only.** Customers continue with magic link
or scan-to-login on a charger. Adding OIDC for customers would require Pocket
ID account provisioning for every EV cardholder, which doesn't match the
business model.

## 13. OIDC mandatory or optional?

**Conflict:** Make OIDC the default, or keep email/password as primary?

**Resolved:** **Three modes, env-driven**:
- `ADMIN_OIDC_ISSUER` unset → email/password only (current behavior).
- Set, no fallback flag → 302 directly to OIDC (no form rendered).
- Set + `ADMIN_AUTH_SHOW_FALLBACK=true` → OIDC button + small "email instead" link.

Email/password is the break-glass for IdP outages. Seed-admin script remains
the bootstrap path.

## 14. Devices table identity: UUID or composite?

**Conflict:** Use UUID (clean, opaque) or `{user_id, device_fingerprint}`
(harder to spoof but couples identity to fingerprinting).

**Resolved:** **UUID** (`gen_random_uuid()`). Server-generated, no
client-supplied state. Spoofing risk is irrelevant because the device's
authority is the bearer token, not the ID.

## 15. APNs token vs cert auth

**Conflict:** Cert auth is legacy but well-understood; token auth is modern.

**Resolved:** **Token-based JWT (ES256)** auth to APNs. Cert renewal pain
isn't worth it. Keys rotate annually with overlap (Apple supports two active
keys per topic).
