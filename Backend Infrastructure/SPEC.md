# Circle Backend — Technical Specification

## 1. Project Overview
Private photo/video sharing backend for small friend groups. Go + SQLite. Self-hosted on NAS/Raspberry Pi. Security and privacy are the highest priorities.

## 2. Directory Structure
```
circle/
├── cmd/
│   └── server/
│       └── main.go              # Application entry point
├── internal/
│   ├── config/
│   │   └── config.go            # App configuration
│   ├── database/
│   │   ├── db.go                # SQLite connection & WAL mode
│   │   └── schema.sql           # Full schema definition
│   ├── middleware/
│   │   ├── auth.go              # JWT validation middleware
│   │   ├── cors.go              # CORS middleware (no wildcard)
│   │   ├── ratelimit.go         # Token bucket rate limiter
│   │   ├── security.go          # Security headers middleware
│   │   └── logger.go            # Request logging (no PII)
│   ├── handlers/
│   │   ├── auth.go              # Login, refresh, password change, logout
│   │   ├── users.go             # User CRUD, admin operations
│   │   ├── posts.go             # Post creation, feed, deletion
│   │   ├── stories.go           # Story creation, listing, view tracking
│   │   ├── likes.go             # Like/unlike
│   │   ├── comments.go          # Comment CRUD
│   │   └── media.go             # Media upload handler
│   ├── models/
│   │   ├── user.go              # User model + queries
│   │   ├── post.go              # Post model + queries
│   │   ├── story.go             # Story model + queries
│   │   ├── like.go              # Like model + queries
│   │   ├── comment.go           # Comment model + queries
│   │   ├── session.go           # Session/JWT model + queries
│   │   └── invite_code.go       # Invite code model + queries
│   ├── storage/
│   │   └── media.go             # Media filesystem operations
│   ├── jobs/
│   │   └── cleanup.go           # Expired story cleanup + orphaned files
│   └── utils/
│       ├── jwt.go               # JWT generate & validate (HS256, 30d expiry)
│       ├── password.go          # bcrypt hash & verify
│       ├── crypto.go            # Secure random generation (passwords, tokens)
│       └── response.go          # HTTP response helpers (JSON, error)
├── web/
│   ├── admin.html               # Admin panel HTML
│   ├── css/
│   │   └── admin.css            # Admin panel styles
│   └── js/
│       └── admin.js             # Admin panel logic
├── Dockerfile
├── docker-compose.yml
├── nginx.conf
├── go.mod
├── go.sum
└── README.md
```

## 3. Technology Stack
- **Go:** 1.22+
- **Router:** `github.com/gin-gonic/gin` v1.9+
- **JWT:** `github.com/golang-jwt/jwt/v5`
- **Password Hashing:** `golang.org/x/crypto/bcrypt`
- **SQLite:** `github.com/mattn/go-sqlite3` v1.14+ with CGO_ENABLED=1
- **UUID:** `github.com/google/uuid`
- **Rate Limiting:** Custom token bucket (in-memory, no Redis)

## 4. Configuration

### 4.1 Environment Variables
| Variable | Default | Description |
|----------|---------|-------------|
| `CIRCLE_PORT` | `8080` | Server port |
| `CIRCLE_DATA_DIR` | `/data` | Data directory path |
| `CIRCLE_JWT_SECRET` | *(required)* | HS256 secret key |
| `CIRCLE_MAX_MEDIA_SIZE` | `50MB` | Max upload size |
| `CIRCLE_ALLOWED_ORIGIN` | *(required)* | CORS origin (no wildcard) |
| `CIRCLE_ADMIN_BIND` | `127.0.0.1` | Admin panel bind address |
| `CIRCLE_RATE_LIMIT` | `100` | Requests per minute per IP |
| `CIRCLE_PASSWORD_COST` | `12` | bcrypt cost factor |

### 4.2 Config Struct
```go
type Config struct {
    Port           string
    DataDir        string
    MediaDir       string // DataDir + "/media"
    DBPath         string // DataDir + "/circle.db"
    JWTSecret      []byte
    MaxMediaSize   int64
    AllowedOrigin  string
    AdminBind      string
    RateLimit      int
    PasswordCost   int
}
```

## 5. Database Layer

### 5.1 Connection
- SQLite with WAL mode (`PRAGMA journal_mode=WAL`)
- `PRAGMA foreign_keys=ON`
- Connection pool: MaxOpenConns=1 (SQLite requirement), MaxIdleConns=1
- Busy timeout: 5000ms (`PRAGMA busy_timeout=5000`)

### 5.2 Schema (see schema.sql for full SQL)
All tables defined in product brief. Key additions:
- `ON DELETE CASCADE` on all FK references
- `UNIQUE` constraints: username, (post_id, user_id) for likes, (story_id, user_id) for views
- Check constraint: stories.media_type IN ('image', 'video')

## 6. Authentication & Security

### 6.1 JWT (HS256)
- Signing: HS256 with `CIRCLE_JWT_SECRET`
- Claims: `sub` (user_id), `username`, `is_admin`, `iat`, `exp` (30 days)
- Storage: iOS Keychain (client responsibility)
- Refresh: New token issued on every authenticated request (sliding window)
- Logout: Token blacklisted in `sessions` table until expiry

### 6.2 Password Security
- Hashing: bcrypt with configurable cost (default 12)
- Temporary passwords: 12 chars, alphanumeric + symbols, securely random
- Password change enforcement: `password_change_required` flag in DB
- No reset flow: admin manually resets

### 6.3 Middleware Stack (execution order)
1. **Recovery** — panic recovery
2. **Security Headers** — HSTS, CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy
3. **Logger** — structured logging, NO PII (no usernames, no IPs in logs)
4. **Rate Limiter** — token bucket, per IP, configurable RPM
5. **CORS** — single allowed origin, credentials enabled, NO wildcard
6. **JWT Auth** — validates Bearer token, sets `user_id` & `is_admin` in context

### 6.4 Rate Limiting
- In-memory token bucket (no external deps)
- Key: SHA256 of IP address (not raw IP in memory)
- Refill: 1 token per `60/ratelimit` seconds
- Burst: equal to rate limit
- Response: `429 Too Many Requests` with `Retry-After` header

## 7. API Specification

### 7.1 Authentication
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/auth/login` | No | Login → JWT |
| POST | `/api/auth/refresh` | Yes | Refresh JWT |
| POST | `/api/auth/change-password` | Yes | Change password |
| POST | `/api/auth/logout` | Yes | Blacklist token |

### 7.2 Users (Admin only for create/delete)
| Method | Path | Auth | Admin | Description |
|--------|------|------|-------|-------------|
| GET | `/api/users` | Yes | Yes | List all users |
| POST | `/api/users` | Yes | Yes | Create user (temp password returned) |
| GET | `/api/users/me` | Yes | No | Get current user |
| PUT | `/api/users/me` | Yes | No | Update display name |
| DELETE | `/api/users/:id` | Yes | Yes | Delete user + cascade |
| POST | `/api/users/:id/reset-password` | Yes | Yes | Reset to temp password |
| POST | `/api/users/:id/toggle-admin` | Yes | Yes | Toggle admin status |

### 7.3 Posts
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/posts` | Yes | Feed (all posts, chronological) |
| GET | `/api/posts/:id` | Yes | Single post |
| POST | `/api/posts` | Yes | Create post + media |
| DELETE | `/api/posts/:id` | Yes | Delete own post (or admin) |

### 7.4 Stories
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/stories` | Yes | Active stories (not expired, not viewed by me) |
| GET | `/api/stories/:id` | Yes | Single story |
| POST | `/api/stories` | Yes | Create story + media |
| POST | `/api/stories/:id/view` | Yes | Mark story as viewed |
| DELETE | `/api/stories/:id` | Yes | Delete own story (or admin) |

### 7.5 Likes & Comments
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/posts/:id/like` | Yes | Toggle like |
| GET | `/api/posts/:id/comments` | Yes | List comments |
| POST | `/api/posts/:id/comments` | Yes | Add comment |
| DELETE | `/api/comments/:id` | Yes | Delete own comment (or admin) |

### 7.6 Media
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/media` | Yes | Upload media file |
| GET | `/media/*` | Yes | Serve media (via nginx, not Go) |

## 8. Media Storage

### 8.1 Upload Flow
1. Client sends multipart/form-data with `media` field
2. Server validates: file type (image/jpeg, image/png, video/mp4, video/quicktime), size, magic bytes
3. Server validates EXIF GPS data is NOT present (reject if GPS found — privacy enforcement)
4. File stored as `/data/media/{user_id}/{uuid}.{ext}`
5. Return `{"filename": "{uuid}.{ext}", "url": "/media/{user_id}/{uuid}.{ext}"}`

### 8.2 Serving
- nginx serves `/media/*` directly with `X-Accel-Redirect` or direct filesystem
- Cache headers: `Cache-Control: private, max-age=31536000`
- No directory listing
- Hidden file deny (.* patterns)

### 8.3 Privacy Enforcement
- Server validates no EXIF GPS data in uploaded images (defense in depth even though iOS strips it)
- Reject uploads with embedded location data
- Log rejection without exposing file content details

## 9. Background Jobs

### 9.1 Story Cleanup (hourly)
```
DELETE FROM stories WHERE expires_at <= datetime('now');
```
- Cascade deletes story_views via FK
- Deletes associated media files from filesystem
- Runs as goroutine with `time.Ticker(1 hour)`

### 9.2 Orphaned Media Cleanup (daily)
- Walk media directory
- Remove files not referenced in posts.media_filename or stories.media_filename
- Log cleanup statistics

## 10. Admin Web Panel

### 10.1 Routes
- `/admin/` → Serves admin.html
- `/admin/*` → Serves admin.html (SPA routing)

### 10.2 Features
- Login with admin credentials
- Dashboard: user count, post count, active stories
- User table: username, display_name, is_admin, created_at
- Create user form: username, display_name
- Actions: reset password, toggle admin, delete user
- All API calls include JWT in Authorization header

### 10.3 Security
- Only accessible when bound to localhost + SSH tunnel
- Admin-only API endpoints return 403 for non-admins
- No stored passwords in localStorage — JWT kept in memory only

## 11. Docker Configuration

### 11.1 Dockerfile
- Multi-stage build
- Stage 1: golang:1.22-alpine with build-base (for CGO/SQLite)
- Stage 2: alpine:latest with ca-certificates
- Copy binary, create /data volume
- Non-root user
- EXPOSE 8080

### 11.2 docker-compose.yml
- Service: `circle-app` — Go backend
- Service: `circle-nginx` — nginx reverse proxy
- Volume: `./data:/data` persistent storage
- Network: internal bridge

### 11.3 nginx.conf
- Listen 80
- `/media/` → root /data/media with cache headers
- `/api/` → proxy_pass http://circle-app:8080
- `/admin/` → proxy_pass http://circle-app:8080
- Deny: `.db`, `.env`, `.*` hidden files
- `X-Real-IP` forwarding for rate limiting

## 12. Error Handling
- All errors: JSON response `{"error": "message"}`
- Status codes: 400 (bad request), 401 (unauthorized), 403 (forbidden), 404 (not found), 429 (rate limit), 500 (server error)
- No stack traces in production responses
- Structured logging with zap or slog

## 13. Response Helpers
```go
func RespondJSON(c *gin.Context, status int, data interface{})
func RespondError(c *gin.Context, status int, message string)
func RespondValidationError(c *gin.Context, fieldErrors map[string]string)
```

## 14. Interface Contracts

### 14.1 Models
```go
type User struct {
    ID                    int64     `json:"id"`
    Username              string    `json:"username"`
    DisplayName           string    `json:"display_name"`
    PasswordHash          string    `json:"-"` // never serialized
    IsAdmin               bool      `json:"is_admin"`
    PasswordChangeRequired bool     `json:"password_change_required"`
    CreatedAt             time.Time `json:"created_at"`
}

type Post struct {
    ID                int64     `json:"id"`
    UserID            int64     `json:"user_id"`
    User              *User     `json:"user,omitempty"`
    Caption           string    `json:"caption"`
    MediaFilename     string    `json:"media_filename"`
    MediaURL          string    `json:"media_url"`
    ThumbnailFilename string    `json:"thumbnail_filename"`
    ThumbnailURL      string    `json:"thumbnail_url"`
    LikeCount         int       `json:"like_count"`
    CommentCount      int       `json:"comment_count"`
    HasLiked          bool      `json:"has_liked"`
    CreatedAt         time.Time `json:"created_at"`
}

type Story struct {
    ID                int64     `json:"id"`
    UserID            int64     `json:"user_id"`
    User              *User     `json:"user,omitempty"`
    MediaFilename     string    `json:"media_filename"`
    MediaURL          string    `json:"media_url"`
    ThumbnailFilename string    `json:"thumbnail_filename"`
    ThumbnailURL      string    `json:"thumbnail_url"`
    MediaType         string    `json:"media_type"`
    CreatedAt         time.Time `json:"created_at"`
    ExpiresAt         time.Time `json:"expires_at"`
    Viewed            bool      `json:"viewed"`
    ViewCount         int       `json:"view_count"`
}

type Comment struct {
    ID        int64     `json:"id"`
    PostID    int64     `json:"post_id"`
    UserID    int64     `json:"user_id"`
    User      *User     `json:"user,omitempty"`
    Text      string    `json:"text"`
    CreatedAt time.Time `json:"created_at"`
}

type Like struct {
    ID        int64     `json:"id"`
    PostID    int64     `json:"post_id"`
    UserID    int64     `json:"user_id"`
    CreatedAt time.Time `json:"created_at"`
}
```

### 14.2 Request/Response Examples
**Login:**
```json
// POST /api/auth/login
{"username": "alice", "password": "secret123"}
// 200 OK
{"token": "eyJhbG...", "user": {"id": 1, "username": "alice", "display_name": "Alice", "is_admin": false, "password_change_required": false}}
```

**Create Post:**
```json
// POST /api/posts (multipart)
// caption=Hello&media_filename=abc123.jpg
// 201 Created
{"id": 1, "caption": "Hello", "media_url": "/media/1/abc123.jpg", ...}
```

**Create User (Admin):**
```json
// POST /api/users
{"username": "bob", "display_name": "Bob"}
// 201 Created
{"user": {"id": 2, ...}, "temporary_password": "xK9#mP2$vL5n"}
```
