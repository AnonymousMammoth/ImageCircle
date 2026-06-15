# PhotoCircle Audit — Prioritized Implementation Review

**Source:** `AUDIT_FINDINGS.md` ( Quality-of-Life Audit )  
**Goal:** Select the highest-impact, lowest-risk fixes that can be delivered in parallel by small, focused implementation teams.

## Executive Summary

This review selects **11 items** across backend, web, and iOS. The selection prioritizes:

1. **Security/correctness bugs** that can cause data corruption, token leakage, or abuse (JWT in URLs, retry of mutating requests, unbounded uploads, rate-limit bypass).
2. **Low-effort / high-impact quick wins** with clearly bounded scope (mark-read notifications, camera WebM fallback, profile metadata, search double-encoding).
3. **Cross-platform consistency** (cookie-based web auth, proxy-aware rate limiting, shared password-strength rules).

The items are grouped into **three parallel implementation batches** plus a small coordination note for a web-auth/backend-auth dependency. No two batches modify the same files.

---

## Batch 1 — Web Authentication & Media Security

**Owner:** Web frontend agent.  
**Theme:** Remove JWT leakage vectors from the web client and rely on the existing `circle_session` HttpOnly cookie.

### 1.1. Stop persisting web JWT in `localStorage`

- **Severity:** HIGH
- **Source finding:** Cross-Platform #2, Web Security #6 (underlying cause)
- **Files to change:**
  - `Backend Infrastructure/project/web/js/state.js`
  - `Backend Infrastructure/project/web/js/app.js`
  - `Backend Infrastructure/project/web/js/components/forcePasswordChange.js`
- **Implementation guidance:**
  1. In `state.js`, remove the `_persistToken()` method and the `loadPersistedToken()` method.
  2. Remove the `this._persistToken()` call inside `setAuth()`.
  3. Keep `clearAuth()` removing the key for one release so existing stored tokens are purged, then remove the `localStorage` interaction entirely.
  4. In `app.js`, delete the `state.loadPersistedToken()` fallback block (lines 58–69) and the `state._persistToken()` call after refresh (lines 47–48). The cookie restore path via `fetchMe()` remains.
  5. In `forcePasswordChange.js`, delete the `state._persistToken()` call after password change (line 76). The refreshed token lives only in memory for that session.
- **Dependencies:** Coordinate with Batch 2 item 2.1 (backend removal of `?token=` fallback). Deploy web changes before or simultaneously with the backend change so media requests continue to work via cookie.
- **Effort:** Small

### 1.2. Remove JWT token query param from media URLs

- **Severity:** HIGH
- **Source finding:** Web Security #6, Cross-Platform #3
- **Files to change:**
  - `Backend Infrastructure/project/web/js/utils.js`
- **Implementation guidance:**
  1. Simplify `authenticatedMediaUrl(url)` to `return url || null;` — do not append `?token=`.
  2. Remove any remaining callers that build manual `?token=` URLs (search `web/js` for `token=`).
  3. `<img>` and `<video>` tags will now authenticate via the `circle_session` cookie on same-origin requests. Verify that `/media/*filepath` is inside the authenticated route group (it is in `cmd/server/main.go`).
- **Dependencies:** Depends on 1.1 (no localStorage token) and 2.1 (backend no longer requires `?token=`). If Safari/PWA cookie issues persist, defer to the blob-media approach listed in **Deferred items**.
- **Effort:** Small

---

## Batch 2 — Backend Security & Infrastructure

**Owner:** Backend agent.  
**Theme:** Close server-side security gaps and make rate limiting work behind nginx.

### 2.1. Remove JWT query-parameter fallback in auth middleware

- **Severity:** CRITICAL
- **Source finding:** Backend Security #1
- **Files to change:**
  - `Backend Infrastructure/project/internal/middleware/auth.go`
- **Implementation guidance:**
  1. Delete lines 49–53 (the `c.Query("token")` fallback block and its comment).
  2. Keep the `Authorization: Bearer <token>` header path and the `circle_session` cookie path.
  3. Update the function comment to remove the query-parameter mention.
  4. Add or extend `middleware/auth_test.go` (if tests are introduced) to assert that `/api/users/me?token=<jwt>` returns 401.
- **Dependencies:** Must be deployed **after or with** Batch 1.1 and 1.2, because the web client currently relies on `?token=` for media URLs. Once the web client stops appending tokens, this fallback is unused and safe to remove.
- **Effort:** Small

### 2.2. Enforce upload size limit on actual bytes read

- **Severity:** HIGH
- **Source finding:** Backend Security #2
- **Files to change:**
  - `Backend Infrastructure/project/internal/storage/media.go`
- **Implementation guidance:**
  1. Keep the early `header.Size > maxSize` check as a fast reject, but do not trust it.
  2. Wrap the final reader passed to `io.Copy` with `io.LimitReader(reader, maxSize+1)`.
  3. After `io.Copy`, if `written > maxSize`, remove the partially written file and return `fmt.Errorf("file too large")`.
  4. Apply the limit **after** `stripImageMetadata()` so a re-encoded image cannot exceed the cap.
     ```go
     var reader io.Reader = file
     if detectedMime == "image/jpeg" || detectedMime == "image/png" {
         if stripped, err := stripImageMetadata(file, detectedMime); err == nil {
             reader = stripped
         }
     }
     lr := io.LimitReader(reader, maxSize+1)
     written, err := io.Copy(dst, lr)
     if err != nil || written > maxSize { ... cleanup ... }
     ```
- **Dependencies:** None.
- **Effort:** Small

### 2.3. Trust proxy headers for rate limiting behind nginx

- **Severity:** HIGH
- **Source finding:** Cross-Platform #1
- **Files to change:**
  - `Backend Infrastructure/project/cmd/server/main.go`
- **Implementation guidance:**
  1. After creating the router (`router := gin.New()`), set:
     ```go
     router.ForwardedByClientIP = cfg.TrustProxy
     if cfg.TrustProxy {
         router.RemoteIPHeaders = []string{"X-Forwarded-For", "X-Real-Ip"}
     }
     ```
  2. The existing `ratelimit.go` already falls back to `c.ClientIP()` when `clientIPExtractor` is nil. `c.ClientIP()` honors `ForwardedByClientIP`, so the rate limiter will see the real client IP when `CIRCLE_TRUST_PROXY=true`.
  3. Document `CIRCLE_TRUST_PROXY` in `Backend Infrastructure/project/README.md` or env example.
- **Dependencies:** None.
- **Effort:** Small

### 2.4. Add notification mark-read endpoint

- **Severity:** HIGH (web-visible bug)
- **Source finding:** Backend UX #16, Web Bugs #2
- **Files to change:**
  - `Backend Infrastructure/project/internal/models/notification.go`
  - `Backend Infrastructure/project/internal/handlers/notifications.go`
  - `Backend Infrastructure/project/cmd/server/main.go`
- **Implementation guidance:**
  1. In `models/notification.go`, add:
     ```go
     func MarkNotificationsRead(db *sql.DB, userID int64) error {
         _, err := db.Exec(`UPDATE notifications SET is_read = 1 WHERE user_id = ? AND is_read = 0`, userID)
         return err
     }
     ```
  2. In `handlers/notifications.go`, add:
     ```go
     func (h *NotificationHandler) MarkRead(c *gin.Context) {
         userID := c.GetInt64("user_id")
         if err := models.MarkNotificationsRead(h.DB, userID); err != nil {
             utils.RespondError(c, http.StatusInternalServerError, "failed to mark notifications read")
             return
         }
         utils.RespondJSON(c, http.StatusOK, gin.H{"ok": true})
     }
     ```
  3. In `cmd/server/main.go`, register under authenticated notifications:
     ```go
     auth.POST("/api/notifications/read", notificationHandler.MarkRead)
     ```
- **Dependencies:** None (this is the backend half of Web item 3.2).
- **Effort:** Small

### 2.5. Return user metadata with empty post lists (backend support for web profile fix)

- **Severity:** HIGH (web-visible bug)
- **Source finding:** Web Bugs #1
- **Files to change:**
  - `Backend Infrastructure/project/internal/handlers/users.go`
- **Implementation guidance:**
  1. In `GetUserPosts`, after validating the user exists, fetch the public user record and include it in the response:
     ```go
     user, err := models.GetUserByID(h.DB, id)
     if err != nil { ... }
     utils.RespondJSON(c, http.StatusOK, gin.H{
         "user":  sanitizePublicUser(user),
         "posts": posts,
     })
     ```
  2. Ensure password hash and sensitive fields are stripped. `GetUserByID` can be reused; just clear `PasswordHash` before serializing.
  3. Alternative: add a dedicated `GET /api/users/:id` endpoint. The embedded-field approach is lower effort and keeps the web client on one request.
- **Dependencies:** Required by Web item 3.1.
- **Effort:** Small

---

## Batch 3 — iOS Correctness & Quality

**Owner:** iOS agent.  
**Theme:** Prevent duplicate mutations, fix encoding, and improve password-change UX.

### 3.1. Restrict `APIClient` retry to idempotent methods

- **Severity:** CRITICAL
- **Source finding:** iOS Bugs #1
- **Files to change:**
  - `ImageCircle/Services/APIClient.swift`
- **Implementation guidance:**
  1. Add a private helper:
     ```swift
     private func isIdempotent(_ request: URLRequest) -> Bool {
         guard let method = request.httpMethod else { return true }
         return ["GET", "HEAD", "OPTIONS", "TRACE"].contains(method.uppercased())
     }
     ```
  2. In both `perform(_:session:retry:)` and `performVoid(_:session:retry:)`, change the retry condition from:
     ```swift
     if retry && shouldRetry(error) { ... }
     ```
     to:
     ```swift
     if retry && isIdempotent(request) && shouldRetry(error) { ... }
     ```
  3. Verify no existing `POST/PUT/DELETE` callers rely on the one-time retry; they should already handle failures explicitly.
- **Dependencies:** None.
- **Effort:** Small

### 3.2. Fix `searchUsers` double-encoding

- **Severity:** HIGH
- **Source finding:** iOS Bugs #2
- **Files to change:**
  - `ImageCircle/Services/APIClient.swift`
- **Implementation guidance:**
  1. In `searchUsers(query:)`, remove the manual `addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)` call.
  2. Set `components.queryItems = [URLQueryItem(name: "q", value: query)]` and let `URLComponents` perform RFC 3986 encoding.
  3. The current code double-encodes characters like space (`%20` → `%2520`), breaking searches with display names.
- **Dependencies:** None.
- **Effort:** Small

### 3.3. Add client-side password-strength validation on iOS

- **Severity:** MEDIUM
- **Source finding:** Cross-Platform #4, iOS UX #15
- **Files to change:**
  - `ImageCircle/Views/Profile/ChangePasswordView.swift`
  - `ImageCircle/Views/Login/ForcePasswordChangeView.swift`
  - Optionally `ImageCircle/Utilities/PasswordValidator.swift` (new shared helper)
- **Implementation guidance:**
  1. Define a minimum rule set matching the backend policy (e.g., ≥8 characters, at least one uppercase, one lowercase, one digit; or use `PasswordValidation` if one exists in the project).
  2. Add a computed `isPasswordStrong` check and a `passwordStrengthHint` string.
  3. Update `canSubmit` in both views to require `isPasswordStrong && newPassword == confirmPassword`.
  4. Show inline feedback (a small `Text` view below the password field) when the password is too weak.
  5. Keep the existing `newPassword.count >= 6` minimum as a floor, but add the stronger rules.
- **Dependencies:** None.
- **Effort:** Small

---

## Batch 4 — Web UX Quick Wins

**Owner:** Web frontend agent (can run in parallel with Batch 1 on separate files).  
**Theme:** Fix obvious broken UX flows on the web client.

### 4.1. Fix profile “User not found” for users with zero posts

- **Severity:** HIGH
- **Source finding:** Web Bugs #1
- **Files to change:**
  - `Backend Infrastructure/project/web/js/components/profile.js`
  - `Backend Infrastructure/project/web/js/api.js` (if new endpoint chosen)
- **Implementation guidance:**
  1. In `profile.js`, stop deriving the profile owner from `posts[0].user`.
  2. Use the `user` field returned by `fetchUserPosts` (added in Batch 2.5). If `data.user` is present, set `this.user = data.user`; otherwise fall back to `posts[0].user` for backward compatibility.
  3. Set `this.userNotFound = true` only when the API returns 404, not when `posts.length === 0`.
  4. If the embedded-field approach is not acceptable, add `fetchUser(userId)` in `api.js` and a new `GET /api/users/:id` handler instead.
- **Dependencies:** Requires Batch 2.5 backend change.
- **Effort:** Small

### 4.2. Clear notification badge when opening the notifications tab

- **Severity:** HIGH
- **Source finding:** Web Bugs #2
- **Files to change:**
  - `Backend Infrastructure/project/web/js/api.js`
  - `Backend Infrastructure/project/web/js/components/notifications.js`
  - `Backend Infrastructure/project/web/js/components/shell.js` (badge updater, if separate)
- **Implementation guidance:**
  1. In `api.js`, add:
     ```js
     async function markNotificationsRead() {
         return apiRequest('POST', '/notifications/read', {});
     }
     ```
  2. In `notifications.js`, at the start of `loadData`, call `await markNotificationsRead()` (inside `try`, non-fatal). On success, call `state.setNotificationCount(0)` and refresh the badge dot in the shell.
  3. Ensure the badge is updated even if the notifications list is already cached (`hasLoaded === true`).
- **Dependencies:** Requires Batch 2.4 backend endpoint.
- **Effort:** Small

### 4.3. Fix camera video recording on Safari/Firefox

- **Severity:** HIGH
- **Source finding:** Web Bugs #3
- **Files to change:**
  - `Backend Infrastructure/project/web/js/components/camera.js`
- **Implementation guidance:**
  1. In `getRecorderMimeType()`, build a fallback chain:
     ```js
     const types = [
         'video/mp4',
         'video/webm;codecs=vp9',
         'video/webm;codecs=vp8',
         'video/webm'
     ];
     for (const type of types) {
         if (MediaRecorder.isTypeSupported(type)) return type;
     }
     return '';
     ```
  2. In `startRecording()`, use the returned `mimeType` for both `MediaRecorder` and the `Blob` constructor.
  3. In `onstop`, set the file extension based on the MIME type (`.mp4` or `.webm`).
  4. If no supported MIME type is found, show a graceful error instead of letting `MediaRecorder` throw.
- **Dependencies:** None.
- **Effort:** Small

---

## Cross-Batch Dependencies & Deployment Order

| Dependency | Must precede |
|------------|--------------|
| Batch 1.1 + 1.2 (web stops using `?token`) | Batch 2.1 (backend removes `?token` fallback) |
| Batch 2.4 (mark-read endpoint) | Batch 4.2 (web calls mark-read) |
| Batch 2.5 (user in posts response) | Batch 4.1 (web profile uses user field) |

**Recommended order:**
1. Merge Batch 1 and Batch 2 together in the same release window (web auth changes land slightly before or with backend auth change).
2. Merge Batch 3 independently (iOS only).
3. Merge Batch 4 after Batch 2 endpoints are live.

---

## Deferred Items

The following findings are valid but are intentionally deferred to keep the first implementation cycle focused and avoid scope creep:

| Finding | Reason for deferral |
|---------|---------------------|
| **Likes/comments ignore blocks** (Backend Security #3) | Security-relevant, but requires adding block checks to multiple handlers and models. Pick up immediately after Batch 2. |
| **Notifications ignore blocks** (Backend Bugs #10) | Same as above; tied to block model changes. |
| **Username uniqueness case-sensitivity** (Backend Security #4) | Medium severity; requires a schema migration and data cleanup. |
| **Auth middleware DB lookup before JWT validation** (Backend Security #6) | Medium severity; reordering is straightforward but needs regression testing for expired-token behavior. |
| **First-admin setup race** (Backend Security #7) | Requires transaction wrapping in admin setup; medium effort. |
| **User deletion misses thumbnails/avatars** (Backend Bugs #8) | Data cleanup bug; should be grouped with broader media lifecycle work. |
| **Story expiry 72h vs docs 24h** (Backend Bugs #9) | Product decision needed on which is correct. |
| **Unread count only counts explicit mentions** (Backend Bugs #11) | Needs product decision on whether likes/comments count as unread. |
| **Reports can target missing content** (Backend Bugs #12) | Low severity; validation can be added with block/report UI work. |
| **ViewStory on expired stories** (Backend Bugs #13) | Low severity; expiry check is small but not user-critical right now. |
| **Avatar upload hardcodes 10MB** (Backend Bugs #14) | Small fix; defer to a media-upload polish pass. |
| **Media served without auth / fetch as blobs** (Web Security #7) | Partially mitigated by Batch 1.2 + Batch 2.1. Full blob-media fetch is the correct long-term fix but requires larger UI changes. |
| **SW cache version-bump only** (Web Security #8) | Medium effort; cache-busting strategy needs design. |
| **Active tab highlight wrong on non-tab routes** (Web UX #9) | Low-medium impact; small fix, but not security-critical. |
| **No pagination on Home/Notifications** (iOS UX #8) | High impact but large effort; requires API pagination contract and SwiftUI infinite-scroll implementation. |
| **No loading state in Profile/Notifications** (iOS UX #9) | UX polish; should be done with pagination work. |
| **No first-admin setup flow / admin report panel in iOS** (iOS Missing Features #16–17) | Large features; require design and backend parity. |
| **Video posts not playable in feed / iOS cannot upload videos to feed** (Cross-Platform #5–6) | Cross-platform media pipeline work; large effort. |
| **Zero automated tests** (Build/Test #1) | Critical long-term, but larger than this cycle. Start adding targeted tests for the items above as they are implemented. |
| **No CI/CD pipeline** (Build/Test #3) | Infrastructure project; not a code fix. |

---

## Suggested Acceptance Criteria

- **Batch 1:** `localStorage` contains no `circle_token`; media `<img>` URLs contain no `?token=`.
- **Batch 2:** `?token=` on any API route returns 401; uploading a file larger than `CIRCLE_MAX_MEDIA_SIZE` is rejected; rate limiter uses `X-Forwarded-For` when `CIRCLE_TRUST_PROXY=true`; `POST /api/notifications/read` clears unread count; `GET /api/users/:id/posts` returns a `user` field even when `posts` is empty.
- **Batch 3:** iOS `POST` requests are not retried after network errors; search for users with spaces/special characters works; weak passwords are rejected before API call.
- **Batch 4:** Viewing a profile with zero posts shows the user header, not “User not found”; opening notifications clears the badge; camera recording works in Safari and Firefox.
