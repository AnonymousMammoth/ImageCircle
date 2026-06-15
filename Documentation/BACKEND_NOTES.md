# Backend Notes — Circle Go API

## Stack

- **Language**: Go 1.22+
- **Router**: [Gin](https://github.com/gin-gonic/gin)
- **Database**: SQLite via `github.com/mattn/go-sqlite3` (CGO_ENABLED=1)
- **JWT**: `github.com/golang-jwt/jwt/v5` (HS256)
- **Password hashing**: `golang.org/x/crypto/bcrypt`
- **UUIDs**: `github.com/google/uuid`
- **EXIF parsing**: `github.com/rwcarlsen/goexif/exif`
- **Rate limiting**: Custom in-memory token bucket
- **Logging**: `log/slog` JSON to stderr

## Entry Point

`cmd/server/main.go` performs the following startup sequence:

1. Loads configuration from environment variables (`internal/config/config.go`).
2. Ensures data directories exist (`/data`, `/data/media`) with `0o700` permissions.
3. Initializes structured JSON logging.
4. Opens SQLite with WAL mode, foreign keys, and busy timeout (`internal/database/db.go`).
5. Creates the `MediaStore` (`internal/storage/media.go`).
6. Creates the in-memory rate limiter.
7. Builds the Gin router and middleware stack.
8. Initializes all handlers and registers routes.
9. Starts the background cleanup job.
10. Starts the HTTP server and waits for `SIGINT`/`SIGTERM` for graceful shutdown.

## Middleware Order

Middleware is applied in this exact order in `main.go`:

1. `gin.Recovery()` — panic recovery.
2. `middleware.SecurityHeaders(cfg.AllowedOrigin)` — HSTS, CSP, X-Frame-Options, etc.
3. `middleware.Logger()` — zero-PII request logging.
4. `middleware.NewRateLimiter(cfg.RateLimit).Middleware()` — token bucket rate limiting.
5. `middleware.NoStoreCacheControl()` — `Cache-Control: no-store` for API/auth responses.
6. `middleware.CORS(cfg.AllowedOrigin)` — single-origin CORS.
7. `middleware.AuthRequired(cfg.JWTSecret)` — applied only to routes inside the `auth` group.

`middleware.AdminRequired()` is applied per-route inside the auth group for admin-only endpoints.

## Handler Responsibilities

| Handler | File | Endpoints | Notes |
|---------|------|-----------|-------|
| `AuthHandler` | `internal/handlers/auth.go` | `/api/admin/setup`, `/api/auth/login`, `/api/auth/refresh`, `/api/auth/change-password`, `/api/auth/logout` | `setup` creates the first admin when no users exist. Login creates a JWT + session row **and sets the `circle_session` cookie**. Logout clears the cookie and deletes the session row. `refresh` and `change-password` also set a fresh cookie. Change password validates strength, clears `password_change_required`, invalidates all other sessions, and returns a fresh token. |
| `UserHandler` | `internal/handlers/users.go` | `/api/users/me`, `/api/users/search`, `/api/users`, `/api/users/:id/*`, `/api/users/me/blocked`, `/api/users/stats` | Search by username/display name. Create/delete/toggle-admin are admin-only. Delete cascades user content. Block/unblock endpoints are idempotent. |
| `PostHandler` | `internal/handlers/posts.go` | `/api/posts`, `/api/posts/:id` | Accepts JSON `{ caption }` for text-only posts or multipart with `media` (and optional `thumbnail`). Validates EXIF GPS. Cleans up files on failure/deletion. |
| `StoryHandler` | `internal/handlers/stories.go` | `/api/stories`, `/api/stories/:id`, `/api/stories/:id/view` | Requires `media_type` and `media`. 24-hour expiry on creation. |
| `LikeHandler` | `internal/handlers/likes.go` | `/api/posts/:id/like` | Toggle like in a transaction. Returns `liked` + `like_count`. |
| `CommentHandler` | `internal/handlers/comments.go` | `/api/posts/:id/comments`, `/api/comments/:id` | Comments limited to 1000 characters. Comments are filtered to exclude authors the requesting user has blocked. |
| `NotificationHandler` | `internal/handlers/notifications.go` | `/api/notifications` | Returns likes and comments on the current user's posts, paginated. |
| `ReportHandler` | `internal/handlers/reports.go` | `/api/reports`, `/api/admin/reports`, `/api/admin/reports/:id` | User reports and admin report management. |
| `MediaHandler` | `internal/handlers/media.go` | `/api/media`, `/media/*filepath` | Generic media upload; authenticated media serving with path sanitization. |

Shared helpers:

- `checkOwnership(c, contentUserID)` — true if the requesting user owns the content or is an admin.
- `detectMimeFromHeader(header)` — magic-byte MIME detection from a `multipart.FileHeader`.

## Model Layer

All SQL/DAO code lives in `internal/models/`:

| File | Responsibility |
|------|----------------|
| `user.go` | User CRUD, password updates, admin toggle. |
| `post.go` | Feed queries, single post with like/comment counts, create/delete. Feed and per-user post queries exclude authors blocked by the requesting user. `posts.media_filename` is nullable to support text-only posts. |
| `story.go` | Active story queries, view tracking, expired story queries, create/delete. Active and per-user story queries exclude authors blocked by the requesting user. |
| `comment.go` | Comment CRUD per post. Comment lists exclude authors blocked by the requesting user. |
| `like.go` | Toggle like transaction, like count, has-liked check. |
| `session.go` | Session create/delete/expiry/blacklist check. |
| `notification.go` | Notification queries for likes/comments on a user's posts. |
| `report.go` | Report creation, admin listing with target info, and status updates. |
| `block.go` | Block/unblock operations and blocked-user ID lookups. |
| `invite_code.go` | Invite code schema helpers (secondary to admin-only creation). |

Rules of thumb:

- All queries use `?` placeholders.
- `User` rows are scanned with the same column order everywhere.
- `PasswordHash` is tagged `json:"-"` and manually cleared before JSON responses; it is also omitted from feed, comment, and story queries.

## Media Storage

Media is stored on the local filesystem under `CIRCLE_DATA_DIR/media/`:

```
/data/media/
  └── {user_id}/
        └── {uuid}.{ext}
```

Example: `/data/media/42/a1b2c3d4-e5f6-7890-abcd-ef1234567890.jpg`.

The `MediaStore` (`internal/storage/media.go`) handles:

- Magic-byte file type detection (JPEG, PNG, MP4, MOV, HEIC).
- File size enforcement.
- UUID filename generation with `os.O_EXCL` to prevent overwrites.
- EXIF GPS validation for JPEG/PNG (rejects if GPS data found).
- File deletion and full-path resolution.

Media is served by the authenticated `MediaHandler.Serve` route (`GET /media/*filepath`). It validates the session, resolves and cleans the path, ensures it stays inside `MediaDir`, and sets `Cache-Control: private`. Direct filesystem serving is no longer used, even behind nginx.

Allowed MIME types:

| MIME type | Extension |
|-----------|-----------|
| `image/jpeg` | `.jpg` |
| `image/png` | `.png` |
| `video/mp4` | `.mp4` |
| `video/quicktime` | `.mov` |
| `image/heic` | `.heic` |

## Web App

`Backend Infrastructure/project/web/` contains a vanilla JS SPA in addition to the admin panel:

- `index.html` is served at `/`.
- `admin.html` and related assets are served at `/admin`.
- Components include feed, stories, camera, notifications, search, profile, settings, and the user admin panel.
- `router.js` is a hash-based SPA router with debouncing and mount tokens to avoid freezing on fast navigation.
- `api.js` stores the JWT in memory and relies on the `circle_session` cookie for media requests.
- The camera component uses `MediaRecorder` for hold-to-record video and tap-to-photo behavior matching the iOS app.

## Background Jobs

`internal/jobs/cleanup.go` runs every hour (configurable):

1. **Delete expired stories**: queries `stories WHERE expires_at <= datetime('now')`, deletes media files, then deletes DB rows.
2. **Delete expired sessions**: removes `sessions` rows past `expires_at`.
3. **Clean orphaned media**: walks `/data/media/` and removes files not referenced by `posts.media_filename`, `posts.thumbnail_filename`, `stories.media_filename`, `stories.thumbnail_filename`, or `users.avatar_filename`. Comparisons use the full `{user_id}/{filename}` relative path to avoid basename collisions.

The job is started in `main.go` and stopped during graceful shutdown.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CIRCLE_PORT` | `8080` | HTTP server port. |
| `CIRCLE_DATA_DIR` | `/data` | Base data directory. The DB lives at `{DataDir}/circle.db` and media at `{DataDir}/media`. |
| `CIRCLE_JWT_SECRET` | *(required)* | HS256 signing secret; must be ≥ 32 bytes. |
| `CIRCLE_ALLOWED_ORIGIN` | *(required)* | Exact CORS origin allowed by the backend. |
| `CIRCLE_MAX_MEDIA_SIZE` | `52428800` (50 MB) | Maximum upload size in bytes. |
| `CIRCLE_RATE_LIMIT` | `100` | Requests per minute per hashed IP. |
| `CIRCLE_PASSWORD_COST` | `12` | bcrypt cost factor. |
| `CIRCLE_COOKIE_SECURE` | `false` | Set to `true` in production to mark the `circle_session` cookie `Secure`. Only enable behind HTTPS. |

## Docker / nginx Wiring

The reference deployment uses two containers defined in `docker-compose.yml`:

- **`circle-app`**: Builds from `Dockerfile`. Not exposed to the host directly; only reachable inside the `circle-network` bridge. The Dockerfile copies the compiled binary **and** the `web/` admin panel assets into the runtime image.
- **`circle-nginx`**: Exposes host port `8080` mapped to container port `80`. Mounts `./data` read-only and `nginx.conf` as the default site.

`nginx.conf` routes:

| Location | Destination | Notes |
|----------|-------------|-------|
| `/media/` | `http://circle-app:8080` | Proxied to Go for authentication; `circle_session` cookie passed for browser requests. |
| `/api/` | `http://circle-app:8080` | Proxy with 60s timeouts and `client_max_body_size 50M`. |
| `/admin` and `/admin/*` | `http://circle-app:8080` | Admin panel SPA. |
| `/` | `http://circle-app:8080` | Web app SPA shell (`index.html`). |
| `~ /\. ` and `~* \.(db\|db-wal\|db-shm\|sqlite\|sqlite3\|env)$` | `deny all` | Hidden and sensitive files blocked. |

The Go backend serves `/media/*` through the authenticated `MediaHandler.Serve` route. There is no `router.Static("/media", ...)` mount.

## Database

- Connection pool: `MaxOpenConns=1`, `MaxIdleConns=1` (required for SQLite).
- Pragmas applied on open:
  - `PRAGMA journal_mode=WAL;`
  - `PRAGMA foreign_keys=ON;`
  - `PRAGMA busy_timeout=5000;`
- Schema is embedded via `//go:embed schema.sql` and executed on startup.
- All foreign keys use `ON DELETE CASCADE`.

## Response Helpers

`internal/utils/response.go` provides consistent JSON responses:

```go
utils.RespondJSON(c, http.StatusOK, data)
utils.RespondError(c, http.StatusBadRequest, "message")
utils.RespondValidationError(c, fieldErrors)
utils.RespondCreated(c, data)
utils.RespondNoContent(c)
```

Use these instead of calling `c.JSON` directly to keep error shapes uniform.

## Adding a New Endpoint

1. Add the route in `cmd/server/main.go` inside the appropriate group.
2. Implement the handler method in the relevant `internal/handlers/*.go` file.
3. Add or update `internal/models/*.go` queries if new DB access is needed.
4. Update [`API_CONTRACT.md`](API_CONTRACT.md) and [`ARCHITECTURE.md`](ARCHITECTURE.md).
5. Add tests if the project has a test pattern for that area (`go test -race -v ./...`).
