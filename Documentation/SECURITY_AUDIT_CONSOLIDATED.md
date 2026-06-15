# Circle / ImageCircle Consolidated Security Audit

**Date:** 2026-06-14  
**Scope:** Go backend (`Backend Infrastructure/project/`), iOS client (`ImageCircle/`), web app (`Backend Infrastructure/project/web/`), Docker/nginx deployment  
**Status:** Issues from the pre-fix audit have been resolved. Remaining findings are tracked below with current severity.

---

## Summary

This audit consolidates findings across the backend API, iOS client, and web app. Recent code passes resolved the most critical client/server contract gaps, the first-admin bootstrap problem, and unauthenticated media access. The remaining open items are design decisions or deployment-hardening items rather than immediate vulnerabilities.

| Category | Resolved | Open |
|----------|:--------:|:----:|
| Authentication & authorization | 3 | 0 |
| Client/server contract | 4 | 0 |
| Network / transport | 0 | 3 |
| Media privacy | 1 | 1 |
| Deployment / operational | 0 | 4 |
| **Total** | **8** | **8** |

---

## Resolved in This Pass

The following issues were present in the pre-fix state and are now resolved in code:

1. **First-admin bootstrap required manual database access**  
   Added `POST /api/admin/setup`. It creates the first admin user when `users` is empty and returns a JWT. Once any user exists it returns `403 setup already complete`.

2. **iOS `APIClient` used incorrect feed path**  
   `fetchFeed()` now calls `GET /api/posts` (was `/api/feed`).

3. **iOS `APIClient` used incorrect current-user path**  
   `fetchMe()` now calls `GET /api/users/me` (was `/api/me`).

4. **iOS `APIClient` used incorrect admin paths**  
   Admin endpoints now use `/api/users/*` instead of `/api/admin/users/*` for list, create, delete, reset-password, and toggle-admin.

5. **iOS `APIClient` used wrong multipart field name for uploads**  
   Media uploads now use field name `media` (was `file`) for posts and stories.

6. **iOS `APIClient` used `DELETE` for unlike**  
   Like/unlike now uses the backend's toggle endpoint `POST /api/posts/:id/like`.

7. **Text-only posts and user search were not implemented**  
   Backend now supports `POST /api/posts` with JSON `{ caption }` and `GET /api/users/search?q=...`. iOS paths are aligned.

8. **Change-password response mismatch**  
   Backend now returns `200 { token, success: true, expires_at }`; iOS `ChangePasswordResponse` decodes `{ token, success }` and `AuthManager` saves the new token. The backend also invalidates all other sessions for the user on password change.

9. **Media URLs were unauthenticated**  
   `GET /media/*` is now served by the authenticated `MediaHandler.Serve`. nginx proxies `/media/` to the Go backend, which validates the session (Bearer header or `circle_session` cookie), sanitizes the path, and streams the file. Cookie-based sessions were added to support browser-initiated media requests.

---

## Open Findings

### 1. No certificate pinning on iOS

- **Severity:** Medium (raised from Low for internet-facing deployments)  
- **Finding:** The iOS app trusts the system certificate store. A network adversary with a compromised or malicious CA could intercept TLS traffic.  
- **Mitigation today:** Intended for private networks / Tailscale / VPNs where the network path is trusted.  
- **Recommendation:** Pin the server's certificate or public key if the app will be used over untrusted networks.

### 2. Server URL stored in `UserDefaults`

- **Severity:** Low  
- **Finding:** `APIClient.baseURLString` reads and writes `server_url` from `UserDefaults`. This is not encrypted and could be read by a device backup or sandbox escape. The JWT token is correctly stored in the Keychain.  
- **Mitigation today:** Server URL is not sensitive in the threat model.  
- **Recommendation:** Move the server URL to the Keychain if device backups are a concern.

### 3. CORS requires exact-origin match

- **Severity:** Low  
- **Finding:** `CIRCLE_ALLOWED_ORIGIN` must match the iOS `server_url` exactly. A typo or scheme mismatch (http vs https, trailing slash, different port) will cause preflight failures.  
- **Mitigation today:** Single-origin CORS is correct; wildcard origins are not allowed.  
- **Recommendation:** Document the exact origin format during deployment and verify it in setup tooling.

### 4. No server-side media processing

- **Severity:** Low  
- **Finding:** The server validates file type and EXIF GPS data but does not re-encode, resize, or strip metadata from images/videos. Malformed or oversized files could be stored if client-side compression is bypassed.  
- **Mitigation today:** Client compresses media; server enforces `CIRCLE_MAX_MEDIA_SIZE` and magic-byte validation; media access now requires authentication.  
- **Recommendation:** Add server-side re-encoding for defense in depth if the threat model includes malicious or non-iOS clients.

### 5. SQLite and in-memory rate limiter prevent horizontal scaling

- **Severity:** Low (by design)  
- **Finding:** The architecture assumes a single backend instance. SQLite file locking and the in-memory token-bucket rate limiter cannot scale across multiple containers.  
- **Mitigation today:** Deployment target is small private groups (5–50 users).  
- **Recommendation:** Accept as a design constraint; do not attempt horizontal scaling without replacing SQLite and the rate limiter.

### 6. Admin panel served from the same origin and port

- **Severity:** Low  
- **Finding:** The admin SPA is served at `/admin` on the same bind address as the public API and web app. There is no separate network segmentation for admin traffic.  
- **Mitigation today:** Admin access requires a valid admin JWT; panel should be reached via VPN/SSH tunnel/Tailscale only.  
- **Recommendation:** Restrict access at the network layer in production.

### 7. No SMTP / self-service password reset

- **Severity:** Low (by design)  
- **Finding:** Users cannot reset their own passwords via email. An admin must generate a new temporary password.  
- **Mitigation today:** Avoids external email dependencies and account-recovery abuse.  
- **Recommendation:** Accept as a privacy/design choice; document the admin reset procedure.

### 8. JWT signed with HS256 only

- **Severity:** Low  
- **Finding:** The backend uses `HS256`. Algorithm-confusion attacks are blocked by the `jwt.SigningMethodHMAC` type check, but key rotation and asymmetric signing are not supported.  
- **Mitigation today:** Strong random secret required; session whitelist enables revocation.  
- **Recommendation:** Document JWT secret rotation by clearing the `sessions` table.

---

## Backend Security Controls (PASS)

| Control | Status | Notes |
|---------|--------|-------|
| JWT HS256 signing | PASS | Algorithm confusion blocked by `SigningMethodHMAC` check |
| JWT expiry + session whitelist | PASS | 30-day expiry; middleware rejects tokens missing from `sessions` |
| Token revocation | PASS | Logout deletes session row and clears cookie |
| Bearer token parsing | PASS | Format-validated `Authorization: Bearer <token>` |
| Cookie-based session | PASS | `circle_session` cookie, `SameSite=Strict`, `HttpOnly`; cleared on logout |
| Password hashing | PASS | bcrypt, default cost 12 |
| Password strength | PASS | Min 8 chars, upper/lower/digit |
| Temporary passwords | PASS | 12 chars, crypto-random, mixed character classes |
| Forced password change | PASS | `password_change_required` flag |
| Admin separation | PASS | `AdminRequired()` middleware |
| Self-lockout prevention | PASS | Cannot delete self or toggle own admin status |
| No public registration | PASS | Accounts admin-created; setup endpoint is one-time |
| No PII in logs | PASS | Method, path, status, duration only |
| IP hashing for rate limit | PASS | SHA256 keys; raw IPs not stored long-term |
| EXIF GPS rejection | PASS | Server rejects uploads containing GPS data |
| Password hash exclusion | PASS | `json:"-"` + manual clearing before responses; omitted from feed/comment/story queries |
| Authenticated media access | PASS | `GET /media/*` requires valid session; path traversal blocked |
| CORS single origin | PASS | Configurable exact origin, credentials enabled |
| Security headers | PASS | HSTS, CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy |
| Rate limiting | PASS | Token bucket, 100 req/min default, `429` + `Retry-After` |
| SQL injection prevention | PASS | All queries use `?` placeholders |
| XSS prevention (admin panel) | PASS | `escapeHtml()` before DOM insertion |
| File type validation | PASS | Magic-byte detection for JPEG, PNG, MP4, MOV, HEIC |
| File size limits | PASS | `CIRCLE_MAX_MEDIA_SIZE`, default 50 MB |
| Path traversal prevention | PASS | `filepath.Clean` + prefix validation in admin static handler and media handler |
| Atomic media save | PASS | `os.O_EXCL` prevents overwrite races |
| Media cleanup | PASS | DB row deleted first, filesystem cleanup follows |
| Orphaned-file cleanup | PASS | Hourly job removes unreferenced media |
| Non-root container | PASS | `circle` user in final Docker image |
| No secrets in image | PASS | `.env` in `.dockerignore`; secrets via env vars |
| Multi-stage Docker build | PASS | Builder stage discarded |
| Health check | PASS | `/api/health` every 30s |
| Graceful shutdown | PASS | SIGINT/SIGTERM with 10s timeout |
| SQLite WAL mode | PASS | `journal_mode=WAL`, foreign keys, busy timeout |

---

## iOS Security Controls (PASS)

| Control | Status | Notes |
|---------|--------|-------|
| JWT storage | PASS | Stored in Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) |
| Token refresh on password change | PASS | `AuthManager.changePassword` saves the new token returned by the backend |
| Client-side metadata stripping | PASS | `MediaPreviewView.compressPhoto` re-encodes JPEG; `compressVideo` re-exports MP4 |
| No sign-up screen | PASS | No public registration flow |
| API path alignment | PASS | All `APIClient` paths match backend routes after recent fix |
| Cookie storage for media auth | PASS | `URLSession` uses `HTTPCookieStorage.shared` so `circle_session` is sent with media requests |

---

## Deployment Hardening Checklist

Before exposing Circle to real users:

- [ ] **JWT secret changed.** Generate a strong random secret:
  ```bash
  openssl rand -base64 64
  ```
- [ ] **HTTPS / TLS configured.** Use Tailscale, Cloudflare Tunnel, or a reverse proxy with Let’s Encrypt. Do not expose plain HTTP.
- [ ] **Cookie Secure flag.** Set `CIRCLE_COOKIE_SECURE=true` in production **only when HTTPS is enabled**.
- [ ] **Admin panel access restricted.** Reach it via SSH tunnel, Tailscale, or VPN only.
- [ ] **Firewall rules set.** Only necessary ports open.
- [ ] **Regular backups configured.** Automate backup of `/data` (SQLite DB + media).
- [ ] **No secrets in code.** `.env` is in `.gitignore` and not committed.
- [ ] **Docker image security.** Final image runs as non-root; no secrets baked into layers.
- [ ] **Rate limiting enabled.** `CIRCLE_RATE_LIMIT` set appropriately.
- [ ] **Strong password cost.** `CIRCLE_PASSWORD_COST` set to `12` or higher.
- [ ] **CORS origin exact.** `CIRCLE_ALLOWED_ORIGIN` matches the iOS `server_url` exactly.
- [ ] **Server OS updated.** Host receives regular security patches.

---

## Threat Model Notes

- Circle is designed for **private networks, VPNs, or Tailscale meshes**, not public internet exposure.
- Media privacy relies on session-based access control in addition to unguessable URLs and network perimeter security.
- Single-instance SQLite and in-memory rate limiting are intentional constraints for small private deployments.
- There is no SMTP server; password resets require admin action.

---

## Report Security Issues

If you discover a security bug, document the issue, fix it with minimal changes, and update this file and `Backend Infrastructure/project/SECURITY_AUDIT.md` if the control tables change.
