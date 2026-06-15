# PhotoCircle Quality-of-Life Audit Findings

Generated from parallel audits of backend, web frontend, iOS frontend, cross-platform gaps, and build/test/deployment.

---

## Backend (Go)

### Security
1. **CRITICAL: JWT accepted via URL query parameter** (`internal/middleware/auth.go:49-53`)
   - `AuthRequired` falls back to `c.Query("token")`, leaking tokens into history/logs/referers.
   - Fix: remove query-param fallback; rely on `Authorization` header / `circle_session` cookie.
2. **HIGH: Upload size limit enforced on client-supplied header** (`internal/storage/media.go:50-52`, `103`)
   - `header.Size` can be spoofed; `io.Copy` is unbounded.
   - Fix: wrap reader in `io.LimitReader(maxSize+1)` and error if exceeded.
3. **HIGH: Likes/comments ignore blocks** (`internal/handlers/likes.go:20-48`, `comments.go:56-96`)
   - Blocked users can still like/comment on blocker posts.
   - Fix: check `models.IsBlocked` before mutating.
4. **MEDIUM: Username uniqueness is case-sensitive** (`schema.sql:4`, `users.go:59`, `auth.go:267`)
   - `alice` and `Alice` can both exist; login uses NOCASE.
   - Fix: add `COLLATE NOCASE` to username column and normalize to lowercase on creation.
5. **MEDIUM: Allowed origin not validated** (`config/config.go:46-49`, `middleware/cors.go:12-16`)
   - Wildcard + credentials is invalid.
   - Fix: reject wildcard origins.
6. **MEDIUM: Auth middleware DB lookup before JWT validation** (`middleware/auth.go:60-77`)
   - Blacklist checked before parsing JWT.
   - Fix: validate JWT first, then check blacklist.
7. **MEDIUM: First-admin setup race** (`auth.go:243-324`)
   - Concurrent setup can create multiple admins.
   - Fix: transaction or atomic insert.

### Bugs
8. **MEDIUM: User deletion misses thumbnails/avatars** (`users.go:571-613`)
   - Fix: include `thumbnail_filename` and `avatar_filename` in cleanup.
9. **MEDIUM: Story expiry 72h vs docs 24h** (`stories.go:113`, docs)
   - Fix: align code/docs.
10. **MEDIUM: Notifications ignore blocks** (`models/notification.go:50-99`)
    - Fix: add block filters.
11. **MEDIUM: Unread count only counts explicit mentions** (`models/notification.go:103-110`)
    - Fix: align count with list or add mark-read endpoints.
12. **LOW: Reports can target missing content** (`reports.go:27-74`)
    - Fix: validate target exists.
13. **LOW: ViewStory on expired stories** (`stories.go:129-156`)
    - Fix: check expiry.
14. **LOW: Avatar upload hardcodes 10MB** (`users.go:373`, `385`)
    - Fix: use configured max size.

### UX
15. **MEDIUM: Viewed stories disappear from feed** (`models/story.go:44-76`)
    - Fix: return all active stories with `viewed` flag.
16. **MEDIUM: No mark-notification-as-read endpoint** (`handlers/notifications.go:13-44`)
    - Fix: add read/mark-read endpoints.

### Build
17. **MEDIUM: Two files not gofmt-clean** (`models/notification.go`, `report.go`)
18. **MEDIUM: docker-compose omits env vars** (`docker-compose.yml`)
19. **LOW: Dockerfile uses `alpine:latest`**
20. **LOW: `make test` lacks CGO_ENABLED=1**

---

## Web Frontend

### Bugs
1. **HIGH: Profile shows “User not found” for users with zero posts** (`js/components/profile.js:38-42`)
   - Fix: fetch user metadata independently of posts.
2. **HIGH: Notification badge never clears** (`js/components/notifications.js`, missing API)
   - Fix: add mark-read endpoint and call it on tab open.
3. **HIGH: Camera video recording fails on Safari/Firefox** (`js/components/camera.js:200-205`)
   - Fix: fallback to `video/webm`.
4. **MEDIUM: Story images use lazy loading** (`js/components/storyViewer.js:322-327`)
   - Fix: eager load active story.
5. **MEDIUM: Failed post media hidden** (`js/components/postCard.js:60-61`)
   - Fix: show placeholder.

### Security
6. **HIGH: JWT appended to media URLs** (`js/utils.js:104-110`)
   - Fix: remove token query param.
7. **MEDIUM: Media served without auth** (`postCard.js`, `storyViewer.js`)
   - Fix: fetch media as blobs with auth (already done for avatars).
8. **MEDIUM: SW cache version-bump only** (`sw.js`)
   - Fix: add hash fingerprints or network-first for shell.

### UX
9. **MEDIUM: Active tab highlight wrong on non-tab routes** (`js/components/shell.js:185-193`)
10. **LOW: Post detail back button uses close icon** (`js/components/postDetail.js:20-22`)
11. **LOW: Pull-to-refresh no visual feedback** (`js/components/home.js:42-57`)
12. **LOW: Search placeholder misleading** (`js/components/search.js:25`)
13. **LOW: Comments sheet doesn’t scroll to new comment** (`js/components/comments.js:150-165`)
14. **LOW: Text-post submit no loading state** (`js/components/composer.js:152-154`)
15. **LOW: Desktop sidebar hint uses touch language** (`js/components/shell.js:158`)

### Missing Features
16. **MEDIUM: No report/block UI for posts/users**
17. **MEDIUM: No share/copy-link**
18. **LOW: Empty states could be friendlier**

---

## iOS Frontend

### Bugs
1. **CRITICAL: Mutating requests auto-retried** (`Services/APIClient.swift:136-169`)
   - Duplicate likes/comments/posts/deletes.
   - Fix: restrict retry to idempotent methods.
2. **HIGH: `searchUsers` double-encodes query** (`APIClient.swift:436-447`)
   - Fix: remove manual percent-encoding.
3. **MEDIUM: `StoryViewerView` pre-fetches videos with image prefetcher** (`StoryViewerView.swift:527-532`)
4. **MEDIUM: Camera `.high` preset may fail** (`CameraView.swift:376`)
5. **MEDIUM: Video thumbnail generation aborts upload on short videos** (`MediaPreviewView.swift:280-303`)
6. **LOW: PostCardView menu condition tautological** (`PostCardView.swift:107`)
7. **LOW: ProfileView debug prints** (`ProfileView.swift:332-334`)

### UX
8. **HIGH: No pagination on Home/Notifications** (`HomeView.swift`, `NotificationsView.swift`, `APIClient.swift`)
9. **HIGH: No loading state in Profile/Notifications** (`ProfileView.swift`, `NotificationsView.swift`)
10. **MEDIUM: SearchView swallows errors** (`SearchView.swift:66-80`)
11. **MEDIUM: No unread badge on Notifications tab** (`MainTabView.swift`)
12. **MEDIUM: Story progress bar doesn’t animate for videos** (`StoryViewerView.swift:316-339`)
13. **MEDIUM: Profile cannot edit display name** (`ProfileView.swift`, `SettingsView.swift`)
14. **LOW: Login doesn’t trim whitespace** (`LoginView.swift`)
15. **LOW: Force password change no show-password toggle** (`ForcePasswordChangeView.swift`)

### Missing Features
16. **HIGH: No first-admin setup flow in iOS** (`LoginView.swift`)
17. **HIGH: No admin report review panel** (`AdminView.swift`)
18. **MEDIUM: No save to photo library**
19. **LOW: No app version in settings**

---

## Cross-Platform / Product

1. **HIGH: Rate limiter sees all clients as 127.0.0.1 behind nginx** (`cmd/server/main.go`, `ratelimit.go`)
   - Fix: set `router.ForwardedByClientIP = cfg.TrustProxy`.
2. **HIGH: Web JWT persisted in localStorage** (`web/js/state.js`)
   - Fix: remove localStorage persistence.
3. **HIGH: JWT in media URLs** (`web/js/utils.js`)
   - Fix: remove token query param.
4. **MEDIUM: iOS password strength not enforced client-side** (`ChangePasswordView`, `ForcePasswordChangeView`)
5. **MEDIUM: Video posts not playable in feed** (both platforms)
6. **MEDIUM: iOS cannot upload videos to feed**
7. **MEDIUM: Web profile lacks report/block actions**
8. **LOW: Feed filtering client-side only**

---

## Build / Test / Deployment

1. **HIGH: Zero automated tests** (backend and iOS)
2. **MEDIUM: Vendored Go toolchain not wired into PATH/docs**
3. **MEDIUM: No CI/CD pipeline**
4. **MEDIUM: Dockerfile uses `alpine:latest`**
5. **LOW: `build.log` not gitignored**
6. **LOW: nginx comment contradicts config**
7. **LOW: `SECURITY_AUDIT.md` stale**

---

## Top Candidate Quick Wins

- Remove JWT query-param fallback in auth middleware.
- Stop persisting web JWT in localStorage.
- Restrict APIClient retry to idempotent methods on iOS.
- Fix iOS search query double-encoding.
- Add web notification mark-read endpoint and clear badge.
- Fix profile “User not found” for empty profiles on web.
- Add camera WebM fallback on web.
- Fix active tab highlighting on non-tab routes.
- Fix iOS password-strength client-side validation.
- Set `ForwardedByClientIP` for rate limiting behind nginx.
