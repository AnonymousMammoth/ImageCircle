# Circle API Contract

This document describes the backend API as it is implemented today in `Backend Infrastructure/project/cmd/server/main.go` and the handler files. All paths assume the prefix `/api`. The iOS client mappings and backend alignment are listed at the end.

## Authentication

All protected endpoints accept either an `Authorization: Bearer <jwt>` header **or** a `circle_session` cookie containing the same JWT. The token must also exist in the `sessions` table and not be expired.

Login, setup, refresh, and change-password set the `circle_session` cookie (`SameSite=Strict`, `HttpOnly`). Logout clears it. Set `CIRCLE_COOKIE_SECURE=true` in production so the cookie is only sent over HTTPS.

### Public endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/api/health` | No | Docker/container health check. Verifies database and storage availability. Returns `{"status": "ok"}` or `503 {"status": "error", "detail": "..."}`. |
| `GET` | `/api/admin/setup` | No | Check whether first-admin setup is still available. Returns `200 {"setup_required": true}` when no users exist, otherwise `403`. |
| `POST` | `/api/admin/setup` | No | One-time first-admin setup. Returns JWT, user object, and expiry. Returns `403` once any user exists. |
| `POST` | `/api/auth/login` | No | Username/password login. Returns JWT, user object, and expiry. |

### Authenticated endpoints

| Method | Path | Admin | Request body / params | Response |
|--------|------|-------|-----------------------|----------|
| `POST` | `/api/auth/refresh` | No | — | `200` `{ token, expires_at }` |
| `POST` | `/api/auth/change-password` | No | JSON `{ current_password, new_password }` | `200` `{ token, success: true, expires_at }` |
| `POST` | `/api/auth/logout` | No | `Authorization` header or cookie | `204` |
| `GET` | `/api/users/me` | No | — | `200` User |
| `PUT` | `/api/users/me` | No | JSON `{ display_name }` | `200` User |
| `GET` | `/api/users/search` | No | Query `q` | `200` `{ users: [...] }` |
| `GET` | `/api/users` | Yes | — | `200` `{ users: [...] }` |
| `POST` | `/api/users` | Yes | JSON `{ username, display_name, is_admin }` | `201` `{ user, temporary_password }` |
| `DELETE` | `/api/users/:id` | Yes | — | `204` |
| `POST` | `/api/users/:id/reset-password` | Yes | — | `200` `{ temporary_password }` |
| `POST` | `/api/users/:id/toggle-admin` | Yes | — | `200` User |
| `GET` | `/api/users/stats` | Yes | — | `200` `{ total_users, total_posts, active_stories }` |
| `POST` | `/api/users/:id/block` | No | — | `200` `{ blocked: true }` |
| `DELETE` | `/api/users/:id/block` | No | — | `200` `{ blocked: false }` |
| `GET` | `/api/users/me/blocked` | No | — | `200` `{ blocked_user_ids: [...] }` |
| `POST` | `/api/reports` | No | JSON `{ target_type, target_id, reason }` | `201` `{ id, status, created_at }` |
| `GET` | `/api/admin/reports` | Yes | Query `status` (`open`, `resolved`, `all`; default `open`) | `200` `{ reports: [...] }` |
| `PUT` | `/api/admin/reports/:id` | Yes | JSON `{ status, resolver_note? }` | `200` Report |
| `GET` | `/api/posts` | No | — | `200` `{ posts: [...] }` |
| `GET` | `/api/posts/:id` | No | — | `200` Post |
| `POST` | `/api/posts` | No | JSON `{ caption }` **or** `multipart/form-data` (`caption`, `media`, optional `thumbnail`) | `201` Post |
| `DELETE` | `/api/posts/:id` | No | — | `204` |
| `GET` | `/api/stories` | No | — | `200` `{ stories: [...] }` |
| `GET` | `/api/stories/:id` | No | — | `200` Story |
| `POST` | `/api/stories` | No | `multipart/form-data` (`media_type`, `media`, optional `thumbnail`) | `201` Story |
| `POST` | `/api/stories/:id/view` | No | — | `204` |
| `DELETE` | `/api/stories/:id` | No | — | `204` |
| `POST` | `/api/posts/:id/like` | No | — | `200` `{ liked, like_count }` |
| `GET` | `/api/posts/:id/comments` | No | — | `200` `{ comments: [...] }` |
| `POST` | `/api/posts/:id/comments` | No | JSON `{ text }` | `201` Comment |
| `DELETE` | `/api/comments/:id` | No | — | `204` |
| `GET` | `/api/notifications` | No | Query `page`, `limit` | `200` `{ notifications: [...] }` |
| `POST` | `/api/media` | No | `multipart/form-data` (`media`) | `200` `{ filename, url }` |

### Static / media

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/media/:user_id/:filename` | Yes (Bearer or `circle_session` cookie) | Uploaded media files. The Go backend serves these via `MediaHandler.Serve` after auth; nginx proxies `/media/` to the Go backend. |
| `GET` | `/admin` | No (admin login required in UI) | Serves the web admin panel SPA. |
| `GET` | `/admin/*` | No | Static files or SPA fallback. |
| `GET` | `/` | No | Serves the web app shell (`web/index.html`). |

## Request / Response Details

### Login

```http
POST /api/auth/login
Content-Type: application/json

{
  "username": "alice",
  "password": "secret123"
}
```

```json
{
  "token": "eyJhbG...",
  "user": {
    "id": 1,
    "username": "alice",
    "display_name": "Alice",
    "is_admin": false,
    "password_change_required": false,
    "created_at": "2026-06-14T10:00:00Z"
  },
  "expires_at": "2026-07-14T10:00:00Z"
}
```

The response also sets the `circle_session` cookie when requested through a browser.

### Create a media post

The backend expects the multipart field name **`media`** (not `file`). The optional thumbnail field is **`thumbnail`**. The caption field is **`caption`**.

```http
POST /api/posts
Authorization: Bearer <token>
Content-Type: multipart/form-data; boundary=----Boundary

------Boundary
Content-Disposition: form-data; name="caption"

Hello from the app
------Boundary
Content-Disposition: form-data; name="media"; filename="photo.jpg"
Content-Type: image/jpeg

<binary image data>
------Boundary
Content-Disposition: form-data; name="thumbnail"; filename="thumb.jpg"
Content-Type: image/jpeg

<binary thumbnail data>
------Boundary--
```

Response (`201 Created`):

```json
{
  "id": 42,
  "user_id": 1,
  "user": { ... },
  "caption": "Hello from the app",
  "media_filename": "a1b2c3d4.jpg",
  "media_url": "/media/1/a1b2c3d4.jpg",
  "thumbnail_filename": "e5f6g7h8.jpg",
  "thumbnail_url": "/media/1/e5f6g7h8.jpg",
  "likes_count": 0,
  "comments_count": 0,
  "has_liked": false,
  "created_at": "2026-06-14T10:05:00Z"
}
```

### Create a story

Stories require **`media_type`** set to `"image"` or `"video"`, plus the **`media`** file. An optional **`thumbnail`** may be included.

```http
POST /api/stories
Authorization: Bearer <token>
Content-Type: multipart/form-data; boundary=----Boundary

------Boundary
Content-Disposition: form-data; name="media_type"

image
------Boundary
Content-Disposition: form-data; name="media"; filename="story.jpg"
Content-Type: image/jpeg

<binary image data>
------Boundary--
```

### Generic media upload

```http
POST /api/media
Authorization: Bearer <token>
Content-Type: multipart/form-data; boundary=----Boundary

------Boundary
Content-Disposition: form-data; name="media"; filename="file.jpg"
Content-Type: image/jpeg

<binary data>
------Boundary--
```

Response:

```json
{
  "filename": "uuid.jpg",
  "url": "/media/1/uuid.jpg"
}
```

### Toggle like

```http
POST /api/posts/42/like
Authorization: Bearer <token>
```

Response:

```json
{
  "liked": true,
  "like_count": 7
}
```

The same endpoint is used for both like and unlike (it toggles).

### Comments

```http
POST /api/posts/42/comments
Authorization: Bearer <token>
Content-Type: application/json

{ "text": "Nice shot!" }
```

```http
GET /api/posts/42/comments
Authorization: Bearer <token>
```

Response:

```json
{
  "comments": [
    {
      "id": 5,
      "post_id": 42,
      "user_id": 2,
      "user": { ... },
      "text": "Nice shot!",
      "created_at": "2026-06-14T10:10:00Z"
    }
  ]
}
```

### Notifications

```http
GET /api/notifications?page=1&limit=20
Authorization: Bearer <token>
```

Response:

```json
{
  "notifications": [
    {
      "id": 123,
      "type": "like",
      "actor": { "id": 2, "username": "bob", "display_name": "Bob", ... },
      "post": {
        "id": 42,
        "user_id": 1,
        "caption": "Hello",
        "media_url": "/media/1/a1b2c3d4.jpg",
        "thumbnail_url": "/media/1/thumb.jpg",
        "created_at": "2026-06-14T10:05:00Z"
      },
      "created_at": "2026-06-14T10:15:00Z"
    },
    {
      "id": 124,
      "type": "comment",
      "actor": { "id": 3, "username": "carol", "display_name": "Carol", ... },
      "post": { ... },
      "comment": {
        "id": 5,
        "text": "Nice shot!",
        "created_at": "2026-06-14T10:20:00Z"
      },
      "created_at": "2026-06-14T10:20:00Z"
    }
  ]
}
```

Notifications are likes and comments on posts owned by the current user, ordered newest first.

### Reports

```http
POST /api/reports
Authorization: Bearer <token>
Content-Type: application/json

{ "target_type": "post", "target_id": 42, "reason": "Inappropriate content" }
```

`target_type` must be `"post"`, `"story"`, or `"user"`. A user cannot report themselves. Response:

```json
{ "id": 7, "status": "open", "created_at": "2026-06-15T10:00:00Z" }
```

Admins list and resolve reports:

```http
GET /api/admin/reports?status=open
Authorization: Bearer <token>
```

```http
PUT /api/admin/reports/7
Authorization: Bearer <token>
Content-Type: application/json

{ "status": "resolved", "resolver_note": "Removed the post" }
```

The report response includes the reporter, target user (when `target_type` is `user`), and target post/story preview fields when applicable.

### Blocks

```http
POST /api/users/5/block
Authorization: Bearer <token>
```

Response: `200 { "blocked": true }`. Blocking is idempotent; blocking an already-blocked user returns `200`. A user cannot block themselves.

```http
DELETE /api/users/5/block
Authorization: Bearer <token>
```

Response: `200 { "blocked": false }`. Unblocking is idempotent.

```http
GET /api/users/me/blocked
Authorization: Bearer <token>
```

Response:

```json
{ "blocked_user_ids": [5, 12] }
```

Content returned by `GET /api/posts`, `GET /api/stories`, `GET /api/users/:id/posts`, and `GET /api/posts/:id/comments` excludes items authored by users the requesting user has blocked.

## Text-Only Post Creation

The iOS client contains a `createTextPost(caption:)` method that sends:

```http
POST /api/posts
Authorization: Bearer <token>
Content-Type: application/json

{ "caption": "A text-only post" }
```

`PostHandler.CreatePost` accepts either the JSON body above or a `multipart/form-data` request with a media file. At least one of `caption` or `media` must be provided. When a text-only post is created, `media_filename` and `thumbnail_filename` are null/empty and `media_url`/`thumbnail_url` are omitted. The schema stores `posts.media_filename` as nullable to support this.

A post is considered text-only when `media_filename` is empty:

```swift
var isTextOnly: Bool { mediaFilename == nil || mediaFilename?.isEmpty == true }
```

## iOS Model Mappings

The iOS app uses `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase` globally, but also defines explicit `CodingKeys` for fields that do not map cleanly or where clarity is preferred.

### `Post` → backend `Post`

| Swift property | JSON key | Notes |
|----------------|----------|-------|
| `id` | `id` | |
| `user` | `user` | Embedded `User` object. |
| `caption` | `caption` | |
| `mediaFilename` | `media_filename` | |
| `thumbnailFilename` | `thumbnail_filename` | |
| `createdAt` | `created_at` | ISO-8601 string. |
| `likesCount` | `likes_count` | |
| `commentsCount` | `comments_count` | |
| `hasLiked` | `has_liked` | |

A post is considered text-only when `mediaFilename` is `nil` or empty:

```swift
var isTextOnly: Bool { mediaFilename == nil || mediaFilename?.isEmpty == true }
```

### `User` → backend `User`

| Swift property | JSON key |
|----------------|----------|
| `id` | `id` |
| `username` | `username` |
| `displayName` | `display_name` |
| `isAdmin` | `is_admin` |
| `passwordChangeRequired` | `password_change_required` |
| `createdAt` | `created_at` |

### `Story` → backend `Story`

| Swift property | JSON key |
|----------------|----------|
| `id` | `id` |
| `user` | `user` |
| `mediaFilename` | `media_filename` |
| `thumbnailFilename` | `thumbnail_filename` |
| `mediaType` | `media_type` | `"image"` or `"video"`. |
| `createdAt` | `created_at` |
| `expiresAt` | `expires_at` |
| `viewed` | `viewed` |

### `Comment` → backend `Comment`

| Swift property | JSON key |
|----------------|----------|
| `id` | `id` |
| `user` | `user` |
| `text` | `text` |
| `createdAt` | `created_at` |

### `AppNotification` → backend `Notification`

| Swift property | JSON key | Notes |
|----------------|----------|-------|
| `id` | `id` | |
| `type` | `type` | `"like"` or `"comment"`. |
| `actor` | `actor` | Embedded `User` object. |
| `post` | `post` | `NotificationPost` (minimal). |
| `comment` | `comment` | Present only for `"comment"` notifications. |
| `createdAt` | `created_at` | ISO-8601 string. |

`NotificationPost` maps `user_id`, `media_url`, and `thumbnail_url`. `NotificationComment` maps `id`, `text`, and `created_at`.

## iOS ↔ Backend Alignment

The iOS `APIClient.swift` is now aligned with the backend routes and field names below. These paths were fixed in the most recent pass; the mismatch table has been retired.

| iOS call | Path it uses | Backend path |
|----------|--------------|--------------|
| `fetchMe()` | `GET /api/users/me` | `GET /api/users/me` |
| `fetchFeed()` | `GET /api/posts` | `GET /api/posts` |
| `searchUsers(q:)` | `GET /api/users/search?q=...` | `GET /api/users/search` |
| `fetchNotifications()` | `GET /api/notifications` | `GET /api/notifications` |
| `adminFetchUsers()` | `GET /api/users` | `GET /api/users` (admin) |
| `adminCreateUser(...)` | `POST /api/users` | `POST /api/users` (admin) |
| `adminDeleteUser(id:)` | `DELETE /api/users/:id` | `DELETE /api/users/:id` (admin) |
| `adminResetPassword(id:)` | `POST /api/users/:id/reset-password` | `POST /api/users/:id/reset-password` (admin) |
| `adminToggleAdmin(id:)` | `POST /api/users/:id/toggle-admin` | `POST /api/users/:id/toggle-admin` (admin) |
| `createPost(...)` | multipart field `media` | multipart field `media` |
| `createStory(...)` | multipart field `media` | multipart field `media` |
| `toggleLike(id:)` / `unlikePost(id:)` | `POST /api/posts/:id/like` | `POST /api/posts/:id/like` (toggle) |
| `createTextPost(caption:)` | `POST /api/posts` JSON `{ caption }` | `POST /api/posts` JSON `{ caption }` |

`ChangePasswordResponse` expects `{ token, success: true }`, matching the backend response.

## First-Admin Setup

There is **no public registration**. The backend provides a one-time setup endpoint that creates the first admin user when no users exist.

### One-time setup endpoint

```http
POST /api/admin/setup
Content-Type: application/json

{
  "username": "admin",
  "password": "YourStrongAdminPassword"
}
```

Response (`200 OK`) when the database has no users:

```json
{
  "token": "eyJhbG...",
  "user": {
    "id": 1,
    "username": "admin",
    "display_name": "admin",
    "is_admin": true,
    "password_change_required": false,
    "created_at": "2026-06-14T10:00:00Z"
  },
  "expires_at": "2026-07-14T10:00:00Z"
}
```

If any user already exists, the endpoint returns `403` `{ "error": "setup already complete" }`. The response also sets the `circle_session` cookie.

### Creating additional users

After setup, create further users via the admin endpoint:

```bash
TOKEN=$(curl -s -X POST https://your-server/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"YourStrongAdminPassword"}' \
  | jq -r '.token')

curl -s -X POST https://your-server/api/users \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"username":"alice","display_name":"Alice","is_admin":false}'
```

The response includes a `temporary_password` that the new user must change on first login.

## Error Format

All errors are returned as JSON:

```json
{ "error": "human-readable message" }
```

Common status codes:

| Status | Meaning |
|--------|---------|
| `400` | Bad request / validation failure |
| `401` | Missing, invalid, revoked, or expired token |
| `403` | Forbidden (not admin, or not owner of content) |
| `404` | Resource not found |
| `429` | Rate limit exceeded (includes `Retry-After` header) |
| `500` | Internal server error |
