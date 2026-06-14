# Circle — Backend Build Plan

## Overview
Build the complete backend for Circle: a private, self-hosted photo/video sharing platform. No iOS frontend — everything server-side, infrastructure, and admin-facing.

## Architecture Stack
- **Go 1.22+** with standard library + minimal deps (gin-gonic/gin, golang-jwt/jwt, x/crypto/bcrypt, mattn/go-sqlite3)
- **SQLite** (WAL mode) — single file, no separate DB process
- **Flat filesystem** for media storage
- **Docker** multi-stage build
- **nginx** reverse proxy + media serving
- **Tailscale-ready** networking

## Stages

### Stage 1 — Project Scaffold & Skill Loading
- Read vibecoding-general-swarm SKILL.md
- Create directory structure
- Initialize Go module

### Stage 2 — Database Layer
- SQLite connection with WAL mode
- Schema creation (all 7 tables)
- Database models & queries
- Migration system
- Connection pooling

### Stage 3 — Core Infrastructure
- Configuration (env vars, config struct)
- Password hashing (bcrypt)
- JWT token generation & validation
- Middleware stack (auth, CORS, rate limiting, logging, recovery)
- Error handling & response helpers

### Stage 4 — Authentication API
- POST /api/auth/login — username/password → JWT
- POST /api/auth/refresh — refresh token
- POST /api/auth/change-password — forced password change flow
- POST /api/auth/logout — invalidate session
- Account creation (admin-only): POST /api/users

### Stage 5 — Media Upload & Storage
- Client-prepared media acceptance (already compressed by iOS)
- Flat filesystem storage: /data/media/{user_id}/{uuid}.{ext}
- Thumbnail handling (server accepts iOS-generated thumbnails)
- nginx direct serving of /media/* with cache headers
- File type validation, size limits
- UUID-based filenames (no metadata leakage)

### Stage 6 — Social API Endpoints
- **Posts:** Create, delete, list feed, get single
- **Stories:** Create, delete, list active, view tracking
- **Likes:** Toggle like/unlike
- **Comments:** Add, delete, list
- **User Profiles:** Get, update display name, list users (admin)

### Stage 7 — Admin Web Panel
- Minimal HTML/CSS/JS served at /admin
- Login page
- User management: list, create, reset password, delete, toggle admin
- Localhost-only binding (127.0.0.1:8080)
- No framework — pure vanilla JS calling /api/*

### Stage 8 — Background Jobs
- Hourly cron: delete expired stories (DB + filesystem)
- Soft/hard delete handling
- Cleanup orphaned media files

### Stage 9 — Docker & Infrastructure
- Multi-stage Dockerfile (builder → runtime)
- docker-compose.yml with nginx + Go app
- nginx.conf: media serving, API proxy, security headers
- .dockerignore
- Tailscale/networking notes

### Stage 10 — Privacy & Security Hardening
- EXIF stripping enforcement (server-side validation)
- No directory listing on /media
- Hidden file blocking (.db, .env)
- Rate limiting: 100 req/min per IP
- CORS: no wildcard, configurable origin
- Security headers (HSTS, CSP, X-Frame-Options)
- Input sanitization
- SQL injection prevention (parameterized queries)
- No logging of sensitive data

## Deliverables
- /mnt/agents/output/circle/ — complete Go backend project
- Dockerfile + docker-compose.yml + nginx.conf
- README with setup instructions
- Security hardening checklist
