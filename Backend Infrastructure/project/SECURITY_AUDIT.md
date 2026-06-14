# Circle Security Audit

**Date:** 2026-06-14  
**Auditor:** Build Agent (automated + manual review)  
**Scope:** Full backend codebase — Go API, SQLite layer, admin panel, Docker, nginx  

---

## 1. Authentication & Authorization

| Control | Status | Notes |
|---------|--------|-------|
| JWT HS256 signing | PASS | Only HMAC-SHA256 accepted; algorithm confusion prevented via `jwt.SigningMethodHMAC` type check |
| JWT expiry (30 days) | PASS | `TokenExpiry = 30 * 24 * time.Hour`; validated in both JWT claims and DB session |
| Token revocation | PASS | Session-based blacklist: logout deletes session row; auth middleware checks sessions table |
| Bearer token extraction | PASS | Proper `Authorization: Bearer <token>` parsing with format validation |
| Password hashing (bcrypt) | PASS | Cost configurable (default 12); `HashPassword` and `VerifyPassword` via `x/crypto/bcrypt` |
| Password strength enforcement | PASS | Min 8 chars, 1 upper, 1 lower, 1 digit |
| Temp password generation | PASS | 12 chars, crypto/rand, guaranteed mix of all character classes |
| Forced password change | PASS | `password_change_required` flag enforced at login response level |
| Admin privilege separation | PASS | `AdminRequired()` middleware on all admin endpoints |
| Self-lockout prevention | PASS | Cannot delete own account or toggle own admin status |
| No public registration | PASS | Only admin-created accounts; invite codes exist but are secondary |

## 2. Data Privacy

| Control | Status | Notes |
|---------|--------|-------|
| No PII in logs | PASS | Logger records method, path, status, duration only — no IPs, usernames, tokens, UAs |
| IP hashing for rate limit | PASS | `HashIP()` uses SHA256; raw IPs never stored in memory long-term |
| EXIF GPS stripping enforcement | PASS | Server validates no GPS data via `goexif`; rejects upload with 400 if found |
| Password hash exclusion | PASS | `json:"-"` tag on `PasswordHash`; manually cleared before JSON serialization |
| No email/phone collection | PASS | Schema has no email/phone fields |
| UUID filenames | PASS | Media stored as UUID + extension; no metadata in filename |
| No analytics/tracking | PASS | No external calls, no tracking pixels, no analytics IDs |

## 3. Network Security

| Control | Status | Notes |
|---------|--------|-------|
| CORS — no wildcard | PASS | Single configurable origin; credentials enabled; preflight handled |
| HSTS header | PASS | `max-age=63072000; includeSubDomains` |
| X-Frame-Options | PASS | `DENY` + CSP `frame-ancestors 'none'` (defense in depth) |
| X-Content-Type-Options | PASS | `nosniff` |
| CSP | PASS | Strict policy: default-src 'self', no inline scripts, no eval, no external resources |
| Referrer-Policy | PASS | `strict-origin-when-cross-origin` |
| Permissions-Policy | PASS | `camera=(), microphone=(), geolocation=()` |
| Rate limiting | PASS | Token bucket, 100 req/min default, SHA256 IP key, 429 + Retry-After |
| No directory listing | PASS | nginx `autoindex off` on /media |
| Hidden file blocking | PASS | nginx denies all `.*` paths; Go admin static handler has path traversal check |
| Media file permissions | PASS | `0o600` (owner read/write only) |
| Data directory permissions | PASS | `0o700` (owner access only) |

## 4. Input Validation & Injection Prevention

| Control | Status | Notes |
|---------|--------|-------|
| SQL injection prevention | PASS | All queries use `?` placeholders; zero string concatenation in queries |
| XSS prevention (admin panel) | PASS | All user data escaped via `escapeHtml()` before DOM insertion |
| File type validation | PASS | Magic bytes detection (not just extension) for JPEG, PNG, MP4, MOV, HEIC |
| File size limits | PASS | Configurable (default 50MB); enforced before write |
| Path traversal prevention | PASS | Admin static handler uses `filepath.Clean` + prefix validation |
| Input sanitization | PASS | Username and display name trimmed; length validated |
| Integer ID parsing | PASS | All route params parsed with `strconv.ParseInt` with error handling |

## 5. Media & Storage Security

| Control | Status | Notes |
|---------|--------|-------|
| Atomic media save | PASS | `os.O_EXCL` flag prevents file overwrite race condition |
| Media cleanup on delete | PASS | DB row deleted first, then filesystem cleanup (no dangling refs) |
| Orphaned file cleanup | PASS | Hourly job removes files not referenced in posts/stories tables |
| Story expiry cleanup | PASS | Expired stories deleted (DB + filesystem) every hour |
| Non-root container | PASS | `circle` user with no login/password in Docker runtime |
| No secrets in image | PASS | All secrets via environment variables; `.env` in `.dockerignore` |

## 6. Infrastructure Security

| Control | Status | Notes |
|---------|--------|-------|
| Multi-stage Docker build | PASS | Builder stage discarded; runtime image ~20MB |
| Health check | PASS | wget against `/api/health` every 30s |
| nginx media direct serving | PASS | Go backend not involved in media delivery |
| nginx hidden file deny | PASS | `.db`, `.env`, `.*` patterns return 404 |
| nginx upload size limit | PASS | `client_max_body_size 50M` matches app limit |
| Graceful shutdown | PASS | SIGINT/SIGTERM handled; 10s timeout for in-flight requests |
| SQLite WAL mode | PASS | `journal_mode=WAL` for better concurrency; foreign keys enabled |
| Connection limits | PASS | MaxOpenConns=1, MaxIdleConns=1 (correct for SQLite) |

## 7. Recommendations (Post-Deploy)

1. **HTTPS/TLS**: Deploy behind Tailscale, Cloudflare Tunnel, or reverse proxy with Let's Encrypt. Never expose HTTP directly to the internet.
2. **Backup**: Schedule regular backups of `/data` (SQLite DB + media). The DB is a single file — easy to copy when the app is running (WAL mode supports this).
3. **JWT Secret Rotation**: The session-based revocation approach means you can rotate secrets by clearing the `sessions` table. Document this procedure.
4. **Monitoring**: The structured JSON logs (slog) can be ingested by any log aggregator. Consider alerting on 429 rate limit events.
5. **Admin Panel Access**: Always access via SSH tunnel (`ssh -L 8080:localhost:8080 nas-host`) or Tailscale. Do not expose port 8080 publicly.

## 8. Known Limitations (By Design)

1. **Single-instance only**: SQLite + in-memory rate limiter means no horizontal scaling. This is by design for a 5-50 user private platform.
2. **No SMTP**: Password resets require admin intervention. This is a privacy feature, not a bug.
3. **No server-side media processing**: All compression/resizing happens on iOS. Server validates but does not transform media.
4. **Token storage**: Admin panel JWT is memory-only (lost on refresh). This is a security feature.

---

**Overall Assessment: PASS**

The Circle backend implements a strong security posture appropriate for a private, self-hosted platform. All critical controls (authentication, authorization, input validation, media privacy, network security) are properly implemented. The architecture correctly prioritizes privacy over convenience (no SMTP, no analytics, no external dependencies).
