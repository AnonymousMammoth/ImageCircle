# Agent Onboarding — Circle / ImageCircle

This guide is for future coding agents. Read it before you make changes.

## Directory Layout

```
/Users/mattmarsh/Documents/PhotoCircle/
├── Documentation/                  # This documentation set
├── ImageCircle/                    # iOS SwiftUI app
│   ├── ImageCircleApp.swift        # App entry point
│   ├── Models/                     # Post, User, Comment, Story, FeedFilter
│   ├── Services/                   # AuthManager, APIClient, KeychainHelper
│   ├── Views/                      # SwiftUI screens
│   │   ├── Home/                   # Feed, PostCard, StoriesTray, StoryViewer
│   │   ├── Camera/                 # Camera, MediaPreview, TextPostComposer
│   │   ├── Profile/                # Profile, Settings, ChangePassword
│   │   ├── Search/                 # Search users
│   │   ├── Admin/                  # iOS admin panel
│   │   └── Login/                  # Login, ForcePasswordChange
│   └── Utilities/                  # View extensions, date helpers, MediaURL
├── ImageCircle.xcodeproj/          # Xcode project
└── Backend Infrastructure/
    ├── project/                    # Go backend (this is the active backend)
    │   ├── cmd/server/main.go      # Entry point
    │   ├── internal/
    │   │   ├── config/             # Env-var config
    │   │   ├── database/           # SQLite connection + schema.sql
    │   │   ├── handlers/           # HTTP route handlers
    │   │   ├── jobs/               # Background cleanup job
    │   │   ├── middleware/         # Auth, admin, CORS, rate limit, security headers, logger
    │   │   ├── models/             # SQL/DAO models
    │   │   ├── storage/            # Media filesystem operations
    │   │   └── utils/              # JWT, bcrypt, crypto, response helpers
    │   ├── web/                    # Vanilla JS admin panel
    │   ├── Dockerfile
    │   ├── docker-compose.yml
    │   ├── nginx.conf
    │   ├── Makefile
    │   ├── .env.example
    │   ├── README.md
    │   └── SECURITY_AUDIT.md
    ├── work-db/                    # Older/experimental Go DB project (not the active backend)
    ├── plan.md
    └── SPEC.md
```

> **Note:** The active backend is `Backend Infrastructure/project/`. The `work-db/` directory is a separate earlier iteration and should not be modified unless explicitly requested.

## How to Build and Test

### Backend

Requirements: Go 1.22+, gcc (for CGO/SQLite).

```bash
cd "/Users/mattmarsh/Documents/PhotoCircle/Backend Infrastructure/project"

# Build
CGO_ENABLED=1 go build -o circle ./cmd/server

# Or use the Makefile
make build

# Run tests
make test
# Equivalent to:
go test -race -v ./...

# Run locally (needs .env)
make run
```

The local server binds to `0.0.0.0:CIRCLE_PORT` (default `8080`). It serves `/media` itself, so nginx is optional for local development.

### iOS

Requirements: macOS, Xcode with iOS 17+ SDK. The project uses the Swift Package Manager dependency `Kingfisher`.

Build command (matches `build.log`):

```bash
cd "/Users/mattmarsh/Documents/PhotoCircle"

xcodebuild -project ImageCircle.xcodeproj \
  -scheme ImageCircle \
  -destination "platform=iOS Simulator,name=iPhone 17,OS=26.1" \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  build CODE_SIGNING_ALLOWED=NO
```

For day-to-day development you can also open `ImageCircle.xcodeproj` in Xcode and build/run from there.

### Docker / Full Stack

```bash
cd "/Users/mattmarsh/Documents/PhotoCircle/Backend Infrastructure/project"

# Create environment file
cp .env.example .env
# Edit .env and set CIRCLE_JWT_SECRET and CIRCLE_ALLOWED_ORIGIN

# Start the stack
make docker-up
# Equivalent to:
# mkdir -p data/media && docker compose up -d

# View logs
make docker-logs

# Stop
make docker-down
```

## Coding Conventions

- **Keep changes minimal.** Do not refactor unrelated code. Do not delete files unless they are clearly dead and you confirm with the user.
- **Match existing style.** Go uses standard `gofmt`-formatted code; Swift uses 4-space indentation and `@MainActor` for shared managers.
- **Backend SQL:** use parameterized queries (`?` placeholders) only. Never concatenate user input into SQL.
- **Backend handlers:** return errors with `utils.RespondError` / `utils.RespondJSON` / `utils.RespondCreated` / `utils.RespondNoContent`.
- **Backend models:** keep DAO functions in the corresponding `internal/models/*.go` file. Always scan `User` rows with the same column order used elsewhere.
- **iOS networking:** route through `APIClient`. Update `APIClient` path strings and multipart field names when the backend contract changes.
- **No new dependencies** without explicit discussion. The project intentionally has a small dependency footprint.
- **Do not commit secrets.** `.env`, data directories, and derived data are already ignored.

## Common Pitfalls

### Backend

1. **The media field name is `media`, not `file`.** The iOS client currently sends `file` in some places; the backend rejects it because it looks for `media`.
2. **SQLite is single-writer.** The connection pool is configured with `MaxOpenConns=1`. Do not add long-running transactions or multiple concurrent writers.
3. **CORS is exact-origin only.** `CIRCLE_ALLOWED_ORIGIN` must match the iOS `server_url` exactly, including scheme and port. Wildcards are not allowed.
4. **Auth middleware checks the `sessions` table.** A valid JWT alone is not enough; the token must be present and not expired in `sessions`. Logout works by deleting the row.
5. **EXIF GPS rejection.** Image uploads with GPS data are rejected with `400 image contains location data`. iOS strips GPS client-side, but the server enforces it as defense-in-depth.
6. **No public registration.** Users are created only by admins via `POST /api/users`.
7. **Admin endpoints use `POST /api/users/:id/...`, not `/api/admin/...`.** The iOS admin paths are currently misaligned.

### iOS

1. **`convertFromSnakeCase` + explicit `CodingKeys`.** `JSONDecoder` converts snake_case automatically, but models still declare explicit `CodingKeys` for clarity. If you add a property, add its key or ensure the automatic conversion works.
2. **Keychain token storage.** `AuthManager` stores the JWT via `KeychainHelper`. Never put tokens in `UserDefaults`.
3. **Server URL in `UserDefaults`.** The server URL itself is stored in `UserDefaults` under `server_url`; the token is not.
4. **Feed filter is client-side.** `FeedFilter` filters the already-fetched `posts` array. There is no backend `?type=` parameter yet.
5. **Text-only posts are not wired up.** `createTextPost(caption:)` sends JSON, but the backend expects multipart media. Do not assume it works end-to-end.
6. **Like endpoint is `POST` toggle only.** The backend does not have a separate `DELETE /api/posts/:id/like`; the iOS `unlikePost` will fail until the backend or the client is changed.
7. **Profile loads posts from the feed.** There is no backend endpoint for a specific user’s posts yet, so `ProfileView` filters the global feed for the current user.

## How to Update These Docs

When you change a contract, route, environment variable, or significant behavior:

1. Update the relevant section in [`API_CONTRACT.md`](API_CONTRACT.md).
2. Update [`BACKEND_NOTES.md`](BACKEND_NOTES.md) or [`FRONTEND_NOTES.md`](FRONTEND_NOTES.md) if the change affects stack, wiring, or iOS behavior.
3. Update [`ARCHITECTURE.md`](ARCHITECTURE.md) if the change affects components or data flow.
4. Update [`SECURITY.md`](SECURITY.md) if the change affects auth, media handling, deployment, or secrets.
5. Mention the doc updates in your final summary.

## Getting Help

- For exact route definitions, see `Backend Infrastructure/project/cmd/server/main.go`.
- For handler logic, see `Backend Infrastructure/project/internal/handlers/`.
- For SQL schema, see `Backend Infrastructure/project/internal/database/schema.sql`.
- For iOS networking, see `ImageCircle/Services/APIClient.swift`.
- For security controls, see `Backend Infrastructure/project/SECURITY_AUDIT.md`.
