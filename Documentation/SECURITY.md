# Circle / ImageCircle Security Notes

This document summarizes the security posture of the backend, mobile-specific notes, and a deployment hardening checklist. It is based on `Backend Infrastructure/project/SECURITY_AUDIT.md` and a review of the iOS code.

## Backend Security Controls

### Authentication & Authorization

| Control | Implementation |
|---------|----------------|
| JWT signing | HS256 only; algorithm confusion blocked by checking `*jwt.SigningMethodHMAC`. |
| Token expiry | 30 days in JWT claims; `sessions.expires_at` also enforced. |
| Token revocation | Logout deletes the session row; auth middleware rejects tokens missing from `sessions`. |
| Bearer parsing | `Authorization: Bearer <token>` validated for format. |
| Cookie-based session | `circle_session` cookie set on login/setup/refresh/change-password; cleared on logout. `SameSite=Strict`, `HttpOnly`; `Secure` controlled by `CIRCLE_COOKIE_SECURE`. |
| Password hashing | bcrypt with configurable cost (default `12`). |
| Password strength | Minimum 8 characters, one uppercase, one lowercase, one digit. |
| Temporary passwords | 12 characters, crypto-random, at least one of each character class. |
| Forced password change | `password_change_required` flag set for new non-admin users. |
| Admin separation | `AdminRequired()` middleware on all admin endpoints. |
| Self-lockout prevention | Users cannot delete themselves or toggle their own admin flag. |
| No public registration | Only admins can create accounts via `POST /api/users`. |

### Data Privacy

| Control | Implementation |
|---------|----------------|
| No PII in logs | Logger records only method, path, status, duration. |
| IP hashing | Rate limiter keys are SHA256 of the client IP; raw IPs are not stored long-term. |
| EXIF GPS rejection | Server validates no GPS data via `goexif`; rejects uploads containing location data. |
| Password hash exclusion | `json:"-"` on `PasswordHash`; manually cleared before JSON serialization; also omitted from feed/comment/story queries. |
| No email/phone collection | Schema has no email or phone fields. |
| UUID filenames | Media stored as `{uuid}.{ext}`; no metadata in filename. |
| Authenticated media access | `GET /media/*` requires a valid session (Bearer or `circle_session` cookie); path sanitized and constrained to the media directory. |
| No analytics / tracking | No external calls, tracking pixels, or analytics IDs. |

### Network Security

| Control | Implementation |
|---------|----------------|
| CORS | Single configurable origin; credentials enabled; no wildcard. |
| HSTS | `max-age=63072000; includeSubDomains`. |
| X-Frame-Options / CSP | `DENY` plus `frame-ancestors 'none'`. |
| X-Content-Type-Options | `nosniff`. |
| CSP | Strict: `default-src 'self'`, no inline scripts, no eval, no external resources. |
| Referrer-Policy | `strict-origin-when-cross-origin`. |
| Permissions-Policy | `camera=(), microphone=(), geolocation=()`. |
| Rate limiting | Token bucket, default 100 req/min per hashed IP, returns `429` + `Retry-After`. |
| Hidden file blocking | nginx denies `.*` paths; Go static handler validates path prefix. |
| Cookie security | `circle_session` is `SameSite=Strict`, `HttpOnly`. Set `CIRCLE_COOKIE_SECURE=true` only behind HTTPS. |
| Media file permissions | Files created with `0o600`; directories with `0o700`. |

### Input Validation & Injection Prevention

| Control | Implementation |
|---------|----------------|
| SQL injection | All queries use `?` placeholders. |
| XSS (admin panel) | User data escaped with `escapeHtml()` before DOM insertion. |
| File type validation | Magic bytes detection for JPEG, PNG, MP4, MOV, HEIC. |
| File size limits | Configurable `CIRCLE_MAX_MEDIA_SIZE` (default 50 MB). |
| Path traversal | Admin static handler and `MediaHandler.Serve` use `filepath.Clean` + prefix validation. |
| Input sanitization | Username/display name trimmed; username length 3–30. |
| Integer IDs | All route params parsed with `strconv.ParseInt`. |

### Media & Storage Security

| Control | Implementation |
|---------|----------------|
| Atomic media save | `os.O_EXCL` prevents overwrite race conditions. |
| Cleanup on delete | DB row deleted first, then filesystem cleanup. |
| Orphaned file cleanup | Hourly job removes files not referenced by posts or stories. |
| Story expiry cleanup | Expired stories removed every hour (DB + filesystem). |
| Non-root container | `circle` user in Docker runtime. |
| No secrets in image | All secrets via environment variables; `.env` in `.dockerignore`. |

### Infrastructure Security

| Control | Implementation |
|---------|----------------|
| Multi-stage Docker build | Builder stage discarded; final Alpine image is small. |
| Health check | wget against `/api/health` every 30s. |
| nginx media serving | nginx proxies `/media/` to Go so the backend can authenticate every request. |
| Graceful shutdown | SIGINT/SIGTERM handled with 10s timeout. |
| SQLite WAL mode | `journal_mode=WAL`; foreign keys enabled; busy timeout 5000 ms. |
| Connection limits | `MaxOpenConns=1`, `MaxIdleConns=1` (correct for SQLite). |

## Mobile-Specific Security Notes

### Token Storage

- The iOS JWT is stored in the Keychain via `KeychainHelper` (`ImageCircle/Services/KeychainHelper.swift`).
- Accessibility level: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- The server URL is stored in `UserDefaults`; the token is not.
- The iOS `URLSession` uses `HTTPCookieStorage.shared`, so the `circle_session` cookie is available for authenticated media requests from `KFImage` and `VideoPlayer`.

### Certificate Pinning

- **Not implemented.** The app trusts the system certificate store. If you deploy behind a custom CA or self-signed certificate, you must either pin a certificate or install the CA on the device.

### Force-Password-Change Flow

- New non-admin accounts are created with `password_change_required = true`.
- `AuthManager.needsPasswordChange` surfaces this flag.
- `LoginView` presents a non-dismissible `ForcePasswordChangeView` after login.
- `AuthManager.changePassword(...)` calls `POST /api/auth/change-password`, saves the new token, and refreshes the current user.

### No Public Registration

- The iOS app has no sign-up screen. Accounts must be created by an admin through the iOS `AdminView` or the web admin panel.

### Media Privacy on Device

- `MediaPreviewView.compressPhoto(_:)` resizes and re-encodes images as JPEG, which strips existing metadata (including GPS).
- `compressVideo(_:)` re-exports video to H.264/AAC MP4.
- The server validates no GPS data remains as defense-in-depth.

## Deployment Hardening Checklist

Before exposing Circle to real users, verify every item:

- [ ] **JWT secret changed.** Generated a strong random secret:
  ```bash
  openssl rand -base64 64
  ```
- [ ] **HTTPS / TLS configured.** Use Tailscale, Cloudflare Tunnel, or a reverse proxy with Let’s Encrypt. Do not expose plain HTTP to the internet.
- [ ] **Cookie Secure flag set.** Set `CIRCLE_COOKIE_SECURE=true` in production **only when HTTPS is enabled**. Leaving it `false` over plain HTTP is required for cookies to be sent.
- [ ] **Admin panel access restricted.** Access via SSH tunnel, Tailscale, or VPN only.
- [ ] **Firewall rules set.** Only necessary ports open (or none if using Tailscale).
- [ ] **Regular backups configured.** Automate backup of `/data` (SQLite DB + media).
- [ ] **No secrets in code.** `.env` is in `.gitignore` and not committed.
- [ ] **Docker image security.** Final image runs as non-root user; no secrets baked into layers.
- [ ] **Rate limiting enabled.** `CIRCLE_RATE_LIMIT` set appropriately for your user count.
- [ ] **Strong password cost.** `CIRCLE_PASSWORD_COST` set to `12` or higher.
- [ ] **Server OS updated.** Host receives regular security patches.
- [ ] **CORS origin exact.** `CIRCLE_ALLOWED_ORIGIN` matches your iOS `server_url` exactly.

## Threat Model Notes

- This app is **not designed for public internet exposure**. It is intended for private networks, VPNs, or Tailscale meshes.
- Media URLs now require a valid session token (Bearer header or `circle_session` cookie). Deep links to `/media/` are rejected for anonymous users.
- SQLite and the in-memory rate limiter mean the system cannot scale horizontally. This is by design for small private deployments.
- There is no SMTP server. Password resets require an admin to generate a new temporary password.

## Report Security Issues

If you discover a security bug, do not commit a fix silently. Document the issue, fix it with minimal changes, and update this file and `Backend Infrastructure/project/SECURITY_AUDIT.md` if the control table changes.
