# ImageCircle Server Setup Notes

Agent-maintained quick-reference for getting the Circle Go backend running. Update this file as we learn more about deployment gotchas.

## What runs where

- Active backend code: `Backend Infrastructure/project/`
- Binary: `Backend Infrastructure/project/circle`
- Runtime config: `Backend Infrastructure/project/.env`
- Data (SQLite + media): `Backend Infrastructure/project/data/`
- Admin panel static files: `Backend Infrastructure/project/web/`

All of the above (`.env`, `circle`, `data/`) are gitignored.

## Requirements

- Go **1.22+** (CGO required for SQLite)
- `gcc`
- Docker is optional but documented in `README.md`; if Docker isn't available, build and run the binary directly.

## Quick start (local binary)

```bash
cd "Backend Infrastructure/project"

# 1. Create environment file
cat > .env << 'EOF'
CIRCLE_JWT_SECRET=$(openssl rand -base64 64)
CIRCLE_ALLOWED_ORIGIN=https://your-domain.example.com
CIRCLE_PORT=8081
CIRCLE_DATA_DIR=./data
EOF

# 2. Create data directory
mkdir -p data/media

# 3. Build
CGO_ENABLED=1 go build -ldflags='-s -w' -o circle ./cmd/server

# 4. Run (loads .env)
set -a && source .env && set +a && ./circle
```

The server binds to `0.0.0.0:CIRCLE_PORT` and serves `/media` and `/admin` itself.

## Environment variables

| Variable | Required | Default | Notes |
|----------|----------|---------|-------|
| `CIRCLE_JWT_SECRET` | yes | — | Min 32 chars. Generate with `openssl rand -base64 64`. |
| `CIRCLE_ALLOWED_ORIGIN` | yes | — | Exact origin the iOS app / browser uses, e.g. `https://imagecircle.example.com`. No wildcards. |
| `CIRCLE_PORT` | no | `8080` | Change if 8080 is already in use (e.g. Pixelfed). |
| `CIRCLE_DATA_DIR` | no | `/data` | Use `./data` for local binary runs. |
| `CIRCLE_MAX_MEDIA_SIZE` | no | `52428800` | 50 MB. |
| `CIRCLE_RATE_LIMIT` | no | `100` | Requests per minute per IP. |
| `CIRCLE_PASSWORD_COST` | no | `12` | bcrypt cost. |

## First admin account

`POST /api/admin/setup` works only when the database has zero users. From the server:

```bash
curl -X POST http://localhost:8081/api/admin/setup \
  -H "Content-Type: application/json" \
  -d '{"username":"matt","password":"YourPassword8!"}'
```

After setup, create further users via the `/admin` web panel or `POST /api/users`.

## Keeping it running

A foreground `./circle` process exits when the shell closes. For a persistent server, use one of:

- **systemd user service** (preferred for a NAS/VM)
- **tmux/screen** session
- **Docker Compose** (see `README.md`) if Docker is available

When running as a background task, make sure the runner does not impose a timeout, or the server will be killed unexpectedly.

## Cloudflare tunnel

Run `cloudflared` pointing at the local port:

```bash
docker run -d --name circle-tunnel --net=host --restart=unless-stopped \
  cloudflare/cloudflared:latest tunnel --no-autoupdate run --token <TOKEN>
```

Important:

1. The tunnel ingress must route the public hostname to `http://localhost:<CIRCLE_PORT>`.
2. Update `CIRCLE_ALLOWED_ORIGIN` to the **exact** public URL (including `https://`) and restart the server. CORS is exact-origin only.
3. The iOS app server URL must also be exactly that public URL, with `https://` and no trailing slash.

## Gotchas we've hit

- **Port 8080 is often taken.** This VM already runs Pixelfed on 8080, so Circle runs on `8081`.
- **System Go may be too old.** Ubuntu 22.04 ships Go 1.18; Circle needs Go 1.22+. Install a newer Go toolchain locally (e.g. `~/.local/go`).
- **CORS must match the browser/app origin exactly.** Using `http://localhost:8081` works for local health checks but breaks the app when served through the tunnel.
- **Background tasks can time out.** If the server stops unexpectedly, check whether the process supervisor killed it.
- **Admin-created users get random temporary passwords.** The `POST /api/users` and reset-password endpoints generate their own passwords; you can't set a custom one through those endpoints. Have the user change it via `/api/auth/change-password`.

## Health checks

```bash
# Local
curl http://localhost:8081/api/health

# Through tunnel
curl https://your-domain.example.com/api/health
```

## Useful logs

```bash
# If running in Docker
docker compose logs -f

# If running the binary directly, logs go to stderr
```
