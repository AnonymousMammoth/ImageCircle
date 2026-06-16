# ImageCircle — Security Audit, Bug Review & Feature Proposals (June 2026)

Scope: full codebase — Go backend (`Backend Infrastructure/project`), web PWA
(`web/`), and the iOS SwiftUI app (`ImageCircle/`).

Overall the project is in good shape. The backend uses parameterized queries
throughout (no SQL injection found), bcrypt password hashing, JWT with HS256
pinning, server-side session tracking for revocation, EXIF/GPS stripping on
image uploads, magic-byte file-type validation, a strict CSP, and path-traversal
guards on every static/media route. The web app renders user data via
`textContent`/`createEl` (no stored XSS in the main PWA), keeps the token in
memory only, and the service worker correctly refuses to cache `/api` and
`/media`. The iOS app stores its token in the Keychain, has no hardcoded
secrets, and does not disable TLS validation.

This document records (1) fixes applied on this branch, (2) remaining
recommendations, (3) bugs, and (4) feature proposals.

---

## 1. Fixes applied on this branch

### 1.1 [High] Rate limiting was disabled behind the nginx proxy
**Files:** `cmd/server/main.go`, `internal/middleware/ratelimit.go`,
`docker-compose.yml`, `.env.example`

The shipped `docker-compose.yml` runs the app behind nginx but never set
`CIRCLE_TRUST_PROXY`. With it unset (`false`), the rate limiter keyed every
request off the connection `RemoteAddr` — which is always the nginx container's
IP. Result: **every client on the platform shared a single rate-limit bucket**.
Two consequences:
- Per-IP brute-force protection on `/api/auth/login` was defeated — an attacker
  and the victim share one counter, and the 10/min "strict" limit applies
  globally rather than per attacker.
- A single client could exhaust the shared bucket and lock everyone out (DoS).

Naively flipping `CIRCLE_TRUST_PROXY=true` would make gin parse
`X-Forwarded-For`, which a client can prepend to and spoof. Instead, the rate
limiter now derives its key from `X-Real-Ip` (new `ClientIPFromXRealIP`
extractor) when trust-proxy is on. nginx sets `X-Real-IP $remote_addr` and
**overwrites** any client-supplied value, so it is not spoofable. The compose
file and `.env.example` now enable and document `CIRCLE_TRUST_PROXY` and
`CIRCLE_COOKIE_SECURE`.

### 1.2 [High] Admin JWT leaked in media thumbnail URLs (web)
**File:** `web/js/admin.js`

Content-review thumbnails were built with
`src="/media/...?token=<JWT>"` (`mediaUrlWithToken`). An admin bearer token in a
URL query string leaks into proxy/access logs, browser history, and `Referer`
headers. The token was also redundant: the media endpoint authenticates the
same-origin `<img>` request via the `circle_session` cookie and never reads a
`token` query param. The token has been removed; thumbnails now load over the
cookie. While here, attribute interpolation switched from `escapeHtml` (which
does not escape quotes) to a new `escapeAttr` helper, closing a latent
attribute-injection vector (currently neutralized by CSP, but defense-in-depth).

### 1.3 [Low/Med] User search returned the entire user table
**File:** `internal/models/user.go`

`SearchUsers` built `"%" + query + "%"` with no `LIMIT` and without escaping LIKE
metacharacters, so `q=a` (or `q=%`) returned every matching user and `%`/`_`
acted as wildcards. Now LIKE metacharacters are escaped (`ESCAPE '\'`) and
results are capped at `LIMIT 50`.

### 1.4 [Med] iOS wiped the stored token on any launch-time network blip
**File:** `ImageCircle/Services/AuthManager.swift`

`loadStoredCredentials()` called `logout()` (which deletes the Keychain token) on
*any* error from `fetchMe()`, including offline/timeout/5xx. Launching the app
once while briefly offline forced a full re-login. It now only clears the token
on `APIError.unauthorized`/`.forbidden`; transient errors keep the token for a
later launch.

### 1.5 [Low] Web `createEl` silently dropped `innerHTML` (functional bug)
**File:** `web/js/utils.js`

`createEl` had no `innerHTML` branch, so `createEl('div', { innerHTML: svg })` in
`login.js` and `forcePasswordChange.js` fell through to
`setAttribute('innerHTML', …)` — a no-op — and the logos never rendered. Added an
`innerHTML` branch (documented as trusted-markup-only).

---

## 2. Remaining security recommendations (not changed — need a product decision)

| # | Severity | Area | Issue | Recommendation |
|---|----------|------|-------|----------------|
| 2.1 | High* | iOS | `login()` accepts explicit `http://` server URLs, sending the bearer token in cleartext. *Severity is conditional: the app is documented to support plain-HTTP LAN deployments, so this is a deliberate tradeoff.* | Keep allowing `http://` only for private/loopback hosts; for any public host, force `https://` or show a "secure server required" warning. Don't rely on ATS alone. |
| 2.2 | Med | iOS | `expires_at` is decoded but never used; expiry handling is purely reactive (act on 401). Expired tokens are replayed each launch. | Persist `expiresAt`; on launch / before requests, if expired, route to login. Pairs with feature 4.1. |
| 2.3 | Med | iOS | `print()` of media URLs / post IDs in `ProfileView.swift` runs in release builds (writes to the unified log). | Wrap in `#if DEBUG` or use `os.Logger` with `.private` redaction. |
| 2.4 | Med | Web/Backend | State-changing requests send the `circle_session` cookie with `credentials:'include'`. CSRF risk depends on the cookie being `SameSite`. | The cookie is set `SameSite=Strict` (`handlers/auth.go setSessionCookie`), which mitigates this. Confirm no flow needs cross-site POST; otherwise add a CSRF token or require the bearer header for mutations. |
| 2.5 | Med | Backend | Any authenticated user can fetch any media via `/media/{uid}/{uuid.ext}`. Mitigated by unguessable UUID filenames, but there is no per-resource authorization (e.g. blocked users, deleted posts). | If stricter privacy is needed, gate `MediaHandler.Serve` on a visibility check, or move to signed, expiring URLs (feature 4.5). |
| 2.6 | Low | Backend | JWT lifetime is 30 days. Revocation works via the sessions table, but a stolen token is valid for a long time. | Shorten access-token TTL and add refresh (feature 4.1). |
| 2.7 | Low | Backend | `UpdateAvatar`/`SaveMedia` accept video MIME types for avatars. | Restrict avatar uploads to `image/jpeg`/`image/png`/`image/heic`. |
| 2.8 | Low | iOS | Keychain item uses `AfterFirstUnlockThisDeviceOnly`; temp password copied to the general (syncable) pasteboard for 30s. | Consider `WhenUnlockedThisDeviceOnly`; set pasteboard `.localOnly` + `.expirationDate`. |
| 2.9 | Low | Backend | No account lockout — only rate limiting protects login. | Add lockout/backoff (feature 4.2). |

\* See the conditional-severity note in the table.

---

## 3. Bugs

Fixed on this branch: 1.1 (rate limiting), 1.4 (iOS logout), 1.5 (logo render).

Still open (low impact):
- **Notifications marked read before fetch** (`web/js/components/notifications.js`):
  `loadData` zeroes the unread badge and calls `markNotificationsRead()` before
  `fetchNotifications()`. If the fetch then fails, the user loses the unread
  indicator for items they never saw. **Fix:** mark read only after a successful
  render, or re-derive the count on failure.
- **iOS `expiresAt` unused** (see 2.2) — latent until a token expires mid-session.

No data-loss or crash bugs were found; force-unwraps in the iOS app are limited
to the safe `AVCaptureVideoPreviewLayer` `layerClass` pattern.

---

## 4. Proposed features with implementation strategies

### 4.1 Token refresh / sliding sessions
**Why:** decouples a short access-token TTL (security) from how often users must
re-authenticate (UX), and makes 2.2/2.6 moot.
**How:** issue a short-lived access JWT (e.g. 1h) plus a long-lived,
DB-backed refresh token (random opaque string in the existing `sessions` table,
rotated on use). Add `POST /api/auth/refresh` to swap a valid refresh token for a
new access token. iOS: store both in Keychain; refresh proactively using the
already-decoded `expires_at`. Web: refresh token stays in the HttpOnly cookie.

### 4.2 Login lockout / exponential backoff
**Why:** rate limiting is per-IP; lockout is per-account.
**How:** track failed attempts per username (in-memory LRU or a small
`login_attempts` table). After N failures, add increasing delay / temporary lock
and surface a generic error. Reset on success. Keep responses constant-time to
avoid username enumeration.

### 4.3 Push notifications (APNs / Web Push) for mentions & likes
**Why:** the notifications table and `@mention` plumbing already exist; only
delivery is missing.
**How:** add a `device_tokens` table (user_id, platform, token). iOS registers
for APNs and `POST`s its token; the web app uses the Push API + the existing
service worker. On notification insert (`createMentionNotifications`, likes),
enqueue a push. Start with a simple synchronous send; move to a worker/queue if
volume grows.

### 4.4 TOTP 2FA for admin accounts
**Why:** admin compromise is the highest-impact threat (user/content management,
password resets).
**How:** add `totp_secret` to `users`; enrollment endpoint returns an
otpauth:// URI / QR; require a TOTP code on admin login and gate
`AdminRequired` flows behind a recent 2FA check. Store recovery codes hashed.

### 4.5 Signed, expiring media URLs
**Why:** closes 2.5 without per-request DB lookups and enables CDN/edge caching.
**How:** sign `/media/...` URLs with an HMAC of `path|exp` using the JWT secret;
`MediaHandler.Serve` verifies the signature and expiry instead of (or in
addition to) the session check. Clients request a signed URL when rendering.

### 4.6 Admin audit log
**Why:** accountability for destructive admin actions (deletes, resets,
admin-toggles).
**How:** an `audit_log` table (actor_id, action, target_type, target_id,
created_at, note) written from the admin handlers; expose a read-only view in the
admin panel.

### 4.7 Server-side image thumbnailing
**Why:** clients currently upload a separate `thumbnail`; the server already
decodes images for EXIF stripping, so it can generate thumbnails itself —
smaller payloads, consistent sizing, less trust in client input.
**How:** in `storage.SaveMedia`, when the type is an image, also produce a
downscaled JPEG via the already-imported `disintegration/imaging` and store it
alongside the original.

---

## 5. Verification

- Backend: `go build ./...` and `go vet ./...` pass.
- Web: `node --check` passes for `admin.js` and `utils.js`.
- iOS: change is localized to `AuthManager.loadStoredCredentials` error handling.
