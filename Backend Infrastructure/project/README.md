# Circle

> A private photo sharing platform for families and close friends.
> Designed for self-hosting on a Raspberry Pi or any small ARM64 server.

Circle is a lightweight, private alternative to cloud photo services. Host it on your own
hardware, keep your photos in your control, and share them only with people you trust.

**Hardware targets:**
- Raspberry Pi 4/5 (4GB+ RAM recommended, 2GB workable)
- Any ARM64 or AMD64 Linux server
- Synology/QNAP NAS via Docker

**Core design:**
- SQLite database (no separate DB server needed)
- Files stored on local filesystem
- Go backend with minimal resource usage
- nginx serves media directly (fast, cached)
- JWT-based authentication
- Admin-created accounts only (no public registration)

---

## Quick Start with Docker

### Prerequisites

- [Docker](https://docs.docker.com/engine/install/) 24.0+
- [Docker Compose](https://docs.docker.com/compose/install/) v2.20+
- 1GB free disk space (plus space for photos)

### 1. Generate a JWT Secret

The JWT secret is used to sign authentication tokens. Generate a strong random secret:

```bash
openssl rand -base64 64
```

Copy the output. This will be your `CIRCLE_JWT_SECRET`.

### 2. Create Environment File

Create a `.env` file in the project root:

```bash
cat > .env << 'EOF'
# Required: JWT signing secret (generate with: openssl rand -base64 64)
CIRCLE_JWT_SECRET=YOUR_GENERATED_SECRET_HERE

# Required: Allowed CORS origin (your frontend URL)
# For Tailscale: https://your-host.tailnet-name.ts.net
# For local dev: http://localhost:8080
CIRCLE_ALLOWED_ORIGIN=https://your-host.tailnet-name.ts.net
EOF
```

**Important:** Never commit the `.env` file to git. It is already in `.gitignore`.

### 3. Create Data Directory

```bash
mkdir -p data/media
```

### 4. Start the Services

```bash
docker compose up -d
```

This builds the Go backend and starts both the app and nginx containers.

### 5. Verify It's Running

```bash
# Check container status
docker compose ps

# View logs
docker compose logs -f

# Test health endpoint
curl http://localhost:8080/api/health
```

### 6. Create First Admin User

The web admin panel is available at `/admin`. You can access it via SSH tunnel:

```bash
# On your local machine, tunnel to the server
ssh -L 8081:localhost:8080 your-server

# Then open http://localhost:8081/admin in your browser
```

Or use the one-time setup API directly:

```bash
curl -X POST http://localhost:8080/api/admin/setup \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"your-secure-password"}'
```

`POST /api/admin/setup` only works when the database has **zero users**. It creates the first admin account and returns a JWT token. After setup, use that token or sign in normally through `/admin`.

---

## Manual Build

If you prefer to run without Docker:

### Requirements

- Go 1.22 or later
- gcc (for CGO/SQLite3 support)
- nginx (recommended for media serving)

### Build

```bash
# Install dependencies
go mod download

# Build with CGO enabled (required for SQLite)
CGO_ENABLED=1 go build -o circle ./cmd/server
```

### Run

```bash
# Set required environment variables
export CIRCLE_PORT=8080
export CIRCLE_DATA_DIR=./data
export CIRCLE_JWT_SECRET=$(openssl rand -base64 64)
export CIRCLE_ALLOWED_ORIGIN=http://localhost:8080

# Create data directory
mkdir -p data/media

# Run
./circle
```

---

## Configuration

All configuration is done via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `CIRCLE_PORT` | `8080` | HTTP server port |
| `CIRCLE_DATA_DIR` | `./data` | Path to data directory (SQLite + media) |
| `CIRCLE_JWT_SECRET` | *(required)* | Secret key for JWT token signing |
| `CIRCLE_ALLOWED_ORIGIN` | *(required)* | CORS allowed origin (your domain) |
| `CIRCLE_MAX_MEDIA_SIZE` | `52428800` (50MB) | Maximum upload file size in bytes |
| `CIRCLE_RATE_LIMIT` | `100` | Requests per minute per IP |
| `CIRCLE_PASSWORD_COST` | `12` | bcrypt password hashing cost (4-31) |
| `CIRCLE_ADMIN_BIND` | `127.0.0.1` | Reserved for future use; currently the backend binds all interfaces |

### Notes

- `CIRCLE_JWT_SECRET`: Must be at least 32 characters. Changing this invalidates all existing login sessions.
- `CIRCLE_PASSWORD_COST`: Higher = more secure but slower. 12 is a good balance. 14+ recommended for sensitive deployments.
- All env vars can be prefixed in a `.env` file and loaded by Docker Compose automatically.

---

## Security Hardening Checklist

Use this checklist before deploying to production:

- [ ] **Changed default JWT secret** -- Generated a strong random secret (`openssl rand -base64 64`)
- [ ] **HTTPS/TLS configured** -- Using Tailscale, reverse proxy with TLS, or both
- [ ] **Admin panel access restricted** -- Behind VPN, Tailscale, or SSH tunnel only
- [ ] **Firewall rules set** -- Only necessary ports open (80/443, or none if using Tailscale)
- [ ] **Regular backups configured** -- Automated backup of `/data` directory (SQLite + media)
- [ ] **No secrets in code** -- Verified `.env` is in `.gitignore` and not committed
- [ ] **Docker image security** -- Using non-root user, no secrets in image layers
- [ ] **Rate limiting enabled** -- `CIRCLE_RATE_LIMIT` set appropriately
- [ ] **Strong password cost** -- `CIRCLE_PASSWORD_COST` set to 12 or higher
- [ ] **Server OS updated** -- Regular security patches applied to host system

### Important Security Notes

**This application is NOT designed for public internet exposure.** It is intended for:
- Private networks (home LAN)
- VPN/Tailscale/WireGuard mesh networks
- SSH-tunnel access only

The admin panel is served at `/admin`. There is no public user registration -- all accounts must be created by an admin. This is by design for a private photo sharing platform.

---

## Admin Panel Access

The admin panel is available at `/admin` on the Go backend (the root path `/` redirects there). In the Docker setup it is exposed through nginx, so protect it with your firewall or reverse proxy and use one of the access methods below.

### Access via SSH Tunnel (Recommended)

```bash
# Local port 8081 -> remote port 8080
ssh -L 8081:localhost:8080 user@your-server

# Open in browser: http://localhost:8081/admin
```

### Access via Tailscale

If both your client and server are on the same Tailscale network:

```
https://your-server.tailnet-name.ts.net/admin
```

### Access via VPN

If connected to the same VPN as the server:

```
http://server-vpn-ip:8080/admin
```

---

## API Endpoints

All authenticated endpoints require a `Bearer` token in the `Authorization` header.

### Authentication

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/api/auth/login` | Public | Authenticate and receive a JWT token |
| `POST` | `/api/auth/refresh` | User | Generate a new JWT token with extended expiry |
| `POST` | `/api/auth/change-password` | User | Change password; invalidates other sessions and returns a fresh token |
| `POST` | `/api/auth/logout` | User | Invalidate the current JWT token |

### Users

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/api/users/me` | User | Get current user profile |
| `PUT` | `/api/users/me` | User | Update current user profile (`display_name`) |
| `GET` | `/api/users/search?q=...` | User | Search users by username or display name |
| `GET` | `/api/users` | Admin | List all users |
| `POST` | `/api/users` | Admin | Create a new user (returns a temporary password) |
| `DELETE` | `/api/users/:id` | Admin | Delete a user and all their content |
| `POST` | `/api/users/:id/reset-password` | Admin | Generate a new temporary password for a user |
| `POST` | `/api/users/:id/toggle-admin` | Admin | Toggle admin status for a user |
| `GET` | `/api/users/stats` | Admin | Platform statistics (users, posts, active stories) |

### Posts

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/api/posts` | User | List the feed of posts |
| `GET` | `/api/posts/:id` | User | Get a single post |
| `POST` | `/api/posts` | User | Create a post. Accepts either `multipart/form-data` (`caption`, `media`, optional `thumbnail`) or JSON `{"caption":"..."}` for text-only posts |
| `DELETE` | `/api/posts/:id` | Owner/Admin | Delete a post and its media files |

### Likes

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/api/posts/:id/like` | User | Toggle a like on a post |

### Comments

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/api/posts/:id/comments` | User | List comments on a post |
| `POST` | `/api/posts/:id/comments` | User | Add a comment to a post |
| `DELETE` | `/api/comments/:id` | Owner/Admin | Delete a comment |

### Stories

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/api/stories` | User | List active stories not yet viewed by the current user |
| `GET` | `/api/stories/:id` | User | Get a single story |
| `POST` | `/api/stories` | User | Create a story (`media_type` of `image` or `video`, plus `media` and optional `thumbnail`) |
| `POST` | `/api/stories/:id/view` | User | Mark a story as viewed |
| `DELETE` | `/api/stories/:id` | Owner/Admin | Delete a story and its media files |

### Media

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/api/media` | User | Upload a generic media file; returns the saved filename and `/media/` URL |

### Admin Setup

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/api/admin/setup` | Public (one-time) | Create the first admin user when no users exist |

### Health

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/api/health` | Public | Health check for Docker/container orchestration |

---

## Backup & Restore

Your data lives in the `/data` directory (mounted as `./data` on the host). This contains:
- `circle.db` -- SQLite database (users, posts, stories, comments, likes, sessions, and invite codes)
- `media/` -- All uploaded photos and videos

### Backup

```bash
# Stop containers to ensure database consistency
docker compose down

# Create backup archive
tar czf circle-backup-$(date +%Y%m%d).tar.gz data/

# Restart containers
docker compose up -d
```

### Automated Backup (cron)

```bash
# Add to crontab: crontab -e
# Daily backup at 3 AM
0 3 * * * cd /path/to/circle && tar czf /backups/circle-$(date +\%Y\%m\%d).tar.gz data/ 2>/dev/null
# Keep last 30 days
find /backups -name 'circle-*.tar.gz' -mtime +30 -delete
```

### Restore

```bash
# Stop containers
docker compose down

# Extract backup
tar xzf circle-backup-20240115.tar.gz

# Restart containers
docker compose up -d
```

### Offsite Backup

For critical photos, consider syncing `/data/media` to:
- [rclone](https://rclone.org/) to cloud storage (encrypted)
- [restic](https://restic.net/) for encrypted incremental backups
- [rsync](https://rsync.samba.org/) to another local server

---

## Updating

### Update to New Version

```bash
# Pull latest code
git pull origin main

# Rebuild and restart
docker compose down
docker compose up -d --build
```

### View Update Logs

```bash
docker compose logs -f --tail=100
```

### Rollback

```bash
# If update fails, revert to previous git commit
git log --oneline -5
git checkout <previous-commit>
docker compose up -d --build
```

---

## Tailscale Setup

[Tailscale](https://tailscale.com/) is the recommended way to expose Circle to your devices without opening firewall ports. It creates an encrypted mesh VPN between your devices.

### 1. Install Tailscale on Server

```bash
# Raspberry Pi / Debian / Ubuntu
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

### 2. Install Tailscale on Client Devices

Install the Tailscale app on your phone, tablet, and computer. Sign in with the same account.

### 3. Access Circle

Your server will have a Tailscale IP (e.g., `100.x.x.x`) and a magic DNS name:

```
https://your-pi.tailnet-name.ts.net:8080
```

### 4. Optional: HTTPS with Tailscale Serve

Tailscale can provide automatic HTTPS certificates:

```bash
sudo tailscale serve --https=443 --set-path=/ http://localhost:8080
```

This gives you a proper `https://` URL without managing certificates.

### 5. Firewall

With Tailscale, you can close all external ports on your server firewall:

```bash
# UFW example
sudo ufw default deny incoming
sudo ufw allow from 100.64.0.0/10  # Tailscale IPs only
sudo ufw enable
```

---

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make build` | Build the Go binary locally |
| `make run` | Run the application locally |
| `make docker-build` | Build the Docker image |
| `make docker-up` | Start all Docker services |
| `make docker-down` | Stop all Docker services |
| `make test` | Run Go tests |
| `make clean` | Remove binary and data directory |

---

## Troubleshooting

### Container fails to start

```bash
# Check logs
docker compose logs circle-app

# Verify environment variables
docker compose exec circle-app env | grep CIRCLE
```

### First-admin setup fails

`POST /api/admin/setup` only works when the database has **zero users**. If setup returns "setup already complete", sign in at `/admin` with an existing admin account, or reset the database/data directory if you are starting fresh.

### Database locked errors

SQLite can have locking issues with concurrent writes. The application handles this with WAL mode and busy timeouts. If issues persist:

```bash
# Check database integrity
docker compose exec circle-app sqlite3 /data/circle.db "PRAGMA integrity_check;"
```

### Out of memory (Raspberry Pi)

Reduce resource limits in `docker-compose.yml`:

```yaml
deploy:
  resources:
    limits:
      memory: 128M  # Reduce from 256M
```

### Permission denied on /data

Ensure the data directory is writable:

```bash
sudo chown -R 1000:1000 ./data
```

---

## License

This project is for personal, non-commercial use.
