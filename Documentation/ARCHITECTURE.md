# Circle / ImageCircle Architecture

## Overview

Circle is a private, self-hosted photo/video sharing app with a Twitter-style text post option. It is designed for small groups (families, close friends) and runs on low-resource hardware such as a Raspberry Pi or a small ARM64 server.

- **iOS app (`ImageCircle/`)**: SwiftUI client that captures/compresses media, browses a feed, views stories, and administers users.
- **Go backend (`Backend Infrastructure/project/`)**: REST API, SQLite persistence, media validation, web app, and admin panel.
- **SQLite database**: Single-file WAL-mode database (`circle.db`).
- **nginx**: Reverse proxy; now proxies media and the web app to the Go backend for authentication.
- **Docker / Docker Compose**: Standard deployment with a Go container and an nginx container.

## Components

| Component | Location | Responsibility |
|-----------|----------|----------------|
| iOS SwiftUI frontend | `ImageCircle/` | User-facing mobile app: auth, feed, stories, camera/text composer, notifications, admin panel. |
| Go API server | `Backend Infrastructure/project/cmd/server/main.go` | HTTP API, JWT/cookie auth, media handling, business logic. |
| Web app + admin panel | `Backend Infrastructure/project/web/` | Vanilla JS SPA served at `/`; admin panel served at `/admin`. Includes feed, stories, camera, notifications, settings, and user admin. |
| Handlers | `Backend Infrastructure/project/internal/handlers/` | Route handlers for auth, users, posts, stories, likes, comments, notifications, media. |
| Models / DAO | `Backend Infrastructure/project/internal/models/` | SQL queries and Go structs for users, posts, stories, comments, likes, sessions, notifications. |
| Storage | `Backend Infrastructure/project/internal/storage/media.go` | File type validation, EXIF GPS rejection, UUID-based filesystem storage. |
| Middleware | `Backend Infrastructure/project/internal/middleware/` | Auth, admin checks, CORS, rate limiting, security headers, zero-PII logging. |
| Background jobs | `Backend Infrastructure/project/internal/jobs/cleanup.go` | Hourly cleanup of expired stories, expired sessions, and orphaned media files. |
| SQLite DB | `Backend Infrastructure/project/internal/database/` | Schema, connection pool, WAL pragmas. |
| nginx | `Backend Infrastructure/project/nginx.conf` | Proxies `/api/*`, `/media/`, `/admin`, and `/` to Go. |
| Docker Compose | `Backend Infrastructure/project/docker-compose.yml` | Orchestrates `circle-app` and `circle-nginx`. |

## Data Flow

```
┌─────────────┐     HTTPS      ┌─────────────┐
│   iOS app   │ ──────────────▶│    nginx    │
└─────────────┘                └──────┬──────┘
                                      │
           ┌──────────────────────────┼──────────────────────────┐
           │ /api/*, /admin, /        │ /media/* (auth via Go)   │
           ▼                          ▼                          ▼
   ┌───────────────┐      ┌─────────────────────┐      ┌─────────────────┐
   │  Go API       │      │  Filesystem         │      │  SQLite         │
   │  (Gin)        │◀────▶│  /data/media/       │      │  /data/circle.db│
   └───────────────┘      └─────────────────────┘      └─────────────────┘
```

1. The iOS app stores the JWT in the Keychain and sends `Authorization: Bearer <token>` on protected requests. The web app relies on the `circle_session` cookie for media and sends the JWT header for API calls.
2. nginx terminates TLS (or sits behind Tailscale/Cloudflare Tunnel) and forwards `/api/*`, `/media/`, `/admin`, and `/` to the Go backend.
3. nginx proxies uploaded photos/videos to the Go backend, which validates the session, sanitizes the path, and streams the file from `/data/media/`.
4. The Go backend reads/writes metadata to SQLite and writes uploaded files to the filesystem.
5. A background goroutine cleans expired stories, expired sessions, and orphaned media files every hour.

## Authentication

- **Mechanism**: JWT signed with HS256, 30-day expiry.
- **Storage**: iOS Keychain (`ImageCircle/Services/KeychainHelper.swift`). The web admin panel keeps its JWT in memory only.
- **Cookie session**: The backend sets a `circle_session` cookie on login, setup, refresh, and change-password so browser-initiated requests (e.g., `<img>` tags) and the web app can present a session without custom headers. The cookie is `SameSite=Strict` and `HttpOnly`; its `Secure` flag is controlled by `CIRCLE_COOKIE_SECURE`. Logout clears the cookie.
- **Session whitelist**: Every login creates a row in the `sessions` table. The auth middleware rejects tokens that are not present (and not expired) in that table, enabling logout/revocation.
- **Refresh**: `POST /api/auth/refresh` issues a new token and new session row.
- **Change password**: `POST /api/auth/change-password` validates the current password, updates the hash, invalidates all other sessions for the user, and returns a fresh token.
- **Forced password change**: New non-admin users are created with `password_change_required = 1`. The iOS app detects this flag and shows a mandatory password-change screen before allowing normal use.
- **First-admin setup**: `POST /api/admin/setup` is a one-time public endpoint that creates the first admin when no users exist. It returns a JWT just like login and sets the session cookie.
- **Admin-only account creation**: There is no public registration after setup. Only admins can create users via `POST /api/users`.

## Security Highlights

- **Password hashing**: bcrypt with configurable cost (default `12`).
- **Rate limiting**: In-memory token bucket per hashed IP; default 100 requests/minute.
- **CORS**: Single allowed origin (`CIRCLE_ALLOWED_ORIGIN`), credentials enabled, no wildcards.
- **Logging**: Zero PII. Logs contain only method, path, status, and duration.
- **Media privacy**: Server validates EXIF GPS data is absent and rejects uploads containing location data. iOS also strips GPS client-side.
- **Media access control**: Files are stored as UUIDs with no metadata in the filename. `/media/` URLs now require a valid session token (Bearer header or `circle_session` cookie); the Go backend validates auth and path before streaming the file.
- **Input safety**: All SQL uses `?` placeholders. File types are validated by magic bytes, not extension. Path traversal is blocked in the admin static-file handler and in `MediaHandler.Serve`.
- **Container hardening**: Non-root user in the final Docker image, multi-stage build, `.env` and `.db` files denied by nginx.

## Deployment Shape

The reference deployment uses Docker Compose:

- `circle-app`: Go backend, no public port exposed, limited to 256 MB RAM / 0.5 CPU.
- `circle-nginx`: nginx reverse proxy, port `8080:80`, proxies media and the web app to Go.
- Persistent state lives in `./data` (SQLite DB + media).

See [`BACKEND_NOTES.md`](BACKEND_NOTES.md) and [`SECURITY.md`](SECURITY.md) for build commands and the deployment checklist.
