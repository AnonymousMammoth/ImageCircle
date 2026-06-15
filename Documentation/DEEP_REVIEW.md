# PhotoCircle Deep UI/UX & Reliability — Focused Sprint Review

**Source:** `Documentation/DEEP_AUDIT.md` and `Documentation/AUDIT_REVIEW.md`  
**Goal:** Select 12 high-impact, tightly-scoped items for a UI/reliability sprint, with web-story reliability as the headline priority. Items are grouped into three parallel batches that avoid conflicting file edits.

---

## Executive Summary

This review selects **12 items** — 8 web, 4 iOS. The selection is intentionally biased toward:

1. **Web story reliability** (the user explicitly reported stories as unreliable).
2. **Silent failures and missing error states** in the highest-traffic screens.
3. **Cross-platform parity** for obvious, high-visibility features (reporting, notification badge, touch targets).
4. **Small, self-contained UI fixes** that can land independently.

Three batches are designed so each can be picked up by a separate coder agent with no overlapping files.

---

## Batch 1 — Web Story Reliability

**Owner:** Web frontend agent.  
**Theme:** Make the web story viewer robust, authenticated, and free of gesture/state bugs.  
**Primary file:** `Backend Infrastructure/project/web/js/components/storyViewer.js`.

### 1.1. Authenticate story media via blob fetch

- **Severity:** HIGH
- **Source finding:** Web Stories #1
- **Files to change:**
  - `Backend Infrastructure/project/web/js/components/storyViewer.js` lines 278–331
  - `Backend Infrastructure/project/web/js/utils.js` lines 142–161 (reuse `loadAuthenticatedImage` pattern)
- **Implementation guidance:**
  1. Add an async helper `loadAuthenticatedMedia(url)` that `fetch`es the media with `credentials: 'same-origin'` and `Authorization: Bearer <state.token>` when a token exists, then returns a blob URL.
  2. In `renderStoryMedia`, call it for both images and videos and set the resulting blob URL on the element.
  3. For videos, call `load()` after setting `src` and only call `play()` once `loadedmetadata` or `canplay` fires.
  4. Keep the existing `onerror` fallback to a white “Could not load” message if the fetch fails.
- **Dependencies:** None. `state.token` is already available and `authenticatedMediaUrl` no longer appends `?token=`.
- **Effort:** Medium

### 1.2. Remove duplicate touch/pointer handlers in story viewer

- **Severity:** HIGH
- **Source finding:** Web Stories #2
- **Files to change:**
  - `Backend Infrastructure/project/web/js/components/storyViewer.js` lines 106–188
- **Implementation guidance:**
  1. Delete the `touchstart`/`touchmove`/`touchend` listeners inside `addTouch`.
  2. Rely solely on `pointerdown`, `pointermove`, `pointerup`, and `pointerleave`.
  3. Ensure `pointerdown` calls `el.setPointerCapture(e.pointerId)` so `pointerup` reliably fires even if the pointer leaves the element.
  4. Keep the long-press/drag-close logic unchanged except for removing the duplicate event sources.
- **Dependencies:** None; ideally land before or with 1.3.
- **Effort:** Small

### 1.3. Pause and detach old video before replacing media

- **Severity:** HIGH
- **Source finding:** Web Stories #3
- **Files to change:**
  - `Backend Infrastructure/project/web/js/components/storyViewer.js` lines 270–334
- **Implementation guidance:**
  1. Before removing `#story-media`, find the existing `<video>` inside it, call `pause()`, set `src = ''`, and call `load()` to detach the decoder.
  2. If `this.currentMedia` is a video, clear its event listeners (`ended`, `loadedmetadata`, `error`, `timeupdate`) before dropping the reference.
  3. After replacement, set `this.currentMedia = null` only after cleanup.
- **Dependencies:** 1.2 makes the gesture surface single-source, reducing the chance of navigation races.
- **Effort:** Small

### 1.4. Add video progress and stop rebuilding progress bars every tick

- **Severity:** MEDIUM
- **Source finding:** Web Stories #5, #7
- **Files to change:**
  - `Backend Infrastructure/project/web/js/components/storyViewer.js` lines 285–320, 336–365
- **Implementation guidance:**
  1. Build the progress bar DOM once per story group in `render()` or in a dedicated `createProgressBars()` method, storing references to each fill element (e.g., in `this.progressFills`).
  2. Update only `fill.style.width` in the timer loop and in video `timeupdate`.
  3. For videos, add a `timeupdate` listener that sets `this.progress = video.currentTime / video.duration` and updates the fill width.
  4. Cap the timer at the actual video duration (read from `video.duration`) rather than the fixed 5s image duration.
- **Dependencies:** 1.1 (blob fetch) ensures the video element is reliably loaded before `timeupdate` fires.
- **Effort:** Medium

---

## Batch 2 — Web Feed, Posts & App-Wide Reliability

**Owner:** Web frontend agent.  
**Theme:** Surface errors, stop listener leaks, and add missing cross-platform actions.  
**Primary files:** `home.js`, `composer.js`, `postCard.js`, `app.js`, `app.css`.

### 2.1. Show error state + retry on web feed load failure

- **Severity:** HIGH
- **Source finding:** Web Feed #13
- **Files to change:**
  - `Backend Infrastructure/project/web/js/components/home.js` lines 168–229, 98–132
- **Implementation guidance:**
  1. Add `loadError: null` and `loadErrorMessage: ''` to the component state.
  2. In `loadData`, catch errors, set `this.loadError = err` and `this.loadErrorMessage = err.message`, then render.
  3. In `renderFeed`, when `this.loadError` is set and `this.posts.length === 0`, show an error card with a “Retry” button that calls `this.loadData(token)`.
  4. Clear `loadError` at the start of every `loadData` call.
- **Dependencies:** None.
- **Effort:** Small

### 2.2. Fix pull-to-refresh listener leak and refresh after post creation

- **Severity:** MEDIUM
- **Source finding:** Web Feed #14, #15
- **Files to change:**
  - `Backend Infrastructure/project/web/js/components/home.js` lines 42–57
  - `Backend Infrastructure/project/web/js/components/composer.js` lines 186–207
- **Implementation guidance:**
  1. In `homeComponent.render`, store the `onTouchStart`/`onTouchEnd` references on the component instance so they can be removed. Before attaching new listeners, remove any previously attached ones.
  2. Alternatively, attach the listeners once to a wrapper element that is never re-created, or use a single delegated listener.
  3. In `composerComponent.submitText` and `submitPhoto`, before `router.navigate('/')`, set `homeComponent.hasLoaded = false` so the feed reloads on arrival.
- **Dependencies:** None.
- **Effort:** Small

### 2.3. Add report action to web post cards

- **Severity:** MEDIUM
- **Source finding:** Web Feed #19
- **Files to change:**
  - `Backend Infrastructure/project/web/js/components/postCard.js` lines 47–52, 190–199
- **Implementation guidance:**
  1. In `renderHeader`, when the viewer is **not** the owner, show a “Report” menu item (or separate button) in addition to the owner-only “Delete”.
  2. Reuse the existing `createReport` API helper. Prompt the user for a reason with `prompt()` or a small modal; for this sprint a simple `prompt('Reason for report?')` is acceptable.
  3. Show `showAlert('Report submitted')` on success and `showAlert(err.message)` on failure.
  4. Keep owner delete behavior unchanged.
- **Dependencies:** `createReport` in `api.js` already exists.
- **Effort:** Small

### 2.4. Add web offline indicator

- **Severity:** MEDIUM
- **Source finding:** Web Navigation #34
- **Files to change:**
  - `Backend Infrastructure/project/web/js/app.js`
  - `Backend Infrastructure/project/web/app.css`
- **Implementation guidance:**
  1. In `app.js`, listen for `online`/`offline` events and dispatch a custom event (`circle:connection`) with the online state.
  2. In `shell.js` or directly in `app.js`, render a small fixed banner at the top of the screen when offline (e.g., “You’re offline. Some features may be unavailable.”).
  3. Add a CSS class `.offline-banner` with appropriate z-index and safe-area padding.
  4. Optionally inspect `navigator.onLine` during `init()` to set initial state.
- **Dependencies:** None.
- **Effort:** Small

---

## Batch 3 — iOS Quality & Cross-Platform Parity

**Owner:** iOS agent.  
**Theme:** Fix misleading empty states, add notification parity, and increase touch targets.  
**Primary files:** `MainTabView.swift`, `NotificationsView.swift`, `HomeView.swift`, `PostCardView.swift`, `StoryViewerView.swift`.

### 3.1. Add iOS notification badge and mark-read parity

- **Severity:** HIGH
- **Source finding:** iOS #38
- **Files to change:**
  - `ImageCircle/Views/MainTabView.swift` lines 44–49
  - `ImageCircle/Views/Notifications/NotificationsView.swift` lines 12–18, 132–145
  - `ImageCircle/Services/APIClient.swift` lines 453–458 (`fetchNotifications`)
- **Implementation guidance:**
  1. Add a `@State private var unreadCount: Int = 0` to `MainTabView` and poll the existing `fetchUnreadNotificationCount()` endpoint on appear and on tab selection.
  2. Apply the badge to the notifications tab item using `.badge(unreadCount)`.
  3. In `NotificationsView.loadNotifications`, after fetching, call `APIClient.shared.markNotificationsRead()` (the endpoint already exists in `APIClient.fetchNotifications` path). If it succeeds, post a notification or callback to clear the badge in `MainTabView`.
  4. Ensure the badge is cleared even when the notifications list is empty.
- **Dependencies:** `APIClient` already has `fetchNotifications`, `fetchUnreadNotificationCount`, and the underlying `markNotificationsRead` endpoint exists on the backend.
- **Effort:** Medium

### 3.2. Fix iOS home feed error/empty-state conflict

- **Severity:** MEDIUM
- **Source finding:** iOS #36
- **Files to change:**
  - `ImageCircle/Views/Home/HomeView.swift` lines 55–57, 138–163
- **Implementation guidance:**
  1. Track feed load errors separately from the empty state: add `feedLoadFailed: Bool` to the view state.
  2. In `loadFeed`, when an error occurs set `feedLoadFailed = true` and `errorMessage`.
  3. In the body, only show `emptyState` when `filteredPosts.isEmpty && !isLoading && !feedLoadFailed`.
  4. When `feedLoadFailed` is true, show an inline error card with a retry button that calls `loadFeed()` and resets `feedLoadFailed`.
- **Dependencies:** None.
- **Effort:** Small

### 3.3. Increase iOS post-card touch targets

- **Severity:** MEDIUM
- **Source finding:** iOS #39, Web Feed #21
- **Files to change:**
  - `ImageCircle/Views/Home/PostCardView.swift` lines 193–211
- **Implementation guidance:**
  1. For the Like and Comment buttons, add `.frame(minWidth: 44, minHeight: 44)` and `.contentShape(Rectangle())`.
  2. Keep the visible icon size at 24×24; only the tappable area grows.
  3. Apply the same 44×44 minimum to the header menu button (lines 124–130).
- **Dependencies:** None.
- **Effort:** Small

### 3.4. Fix iOS story-viewer tap-zone overlay ordering

- **Severity:** MEDIUM
- **Source finding:** iOS #40
- **Files to change:**
  - `ImageCircle/Views/Home/StoryViewerView.swift` lines 213–228, 296–314
- **Implementation guidance:**
  1. In `overlayControls`, reorder the ZStack so `bottomInfo` is rendered **after** `tapZones`, making the user info/avatar tappable and visible above the tap zone.
  2. Constrain `tapZones` so it starts below the top bar and ends above the bottom info area, rather than covering the full height.
  3. Ensure the top bar and bottom info remain accessible while left/right taps still navigate.
- **Dependencies:** None.
- **Effort:** Small

---

## Cross-Batch Dependencies & Ordering

| Dependency | Must precede |
|------------|--------------|
| Batch 1.1 (blob fetch) | Batch 1.4 (reliable video `timeupdate`) |
| Batch 1.2 (single pointer source) | Batch 1.3 (cleaner gesture lifecycle) |
| Batch 2.1 + 2.2 (error state + refresh flag) | — |
| Batch 3.1 backend endpoint | Already implemented (`/api/notifications/read`) |

**Recommended order:**
1. Start all three batches in parallel; they touch disjoint files.
2. Within Batch 1, implement in the order 1.2 → 1.3 → 1.1 → 1.4 to avoid gesture and media-cleanup regressions.
3. Merge together once each batch is manually verified on a real mobile browser and the iOS Simulator.

---

## Deferred Items

The following findings from `DEEP_AUDIT.md` are valid but intentionally deferred to keep the sprint focused and avoid scope creep:

| Finding | Reason for deferral |
|---------|---------------------|
| **Story media preloading** (Web Stories #4) | Worthwhile, but requires prefetch queue and cache eviction; build after blob fetch is stable. |
| **Image timer starts before image loads** (Web Stories #6) | Covered implicitly by blob-fetch work; can be a fast follow-up. |
| **Long-press pause triggers tap on release** (Web Stories #9) | Requires pointer-level flag; small but can be combined with preloading work. |
| **Story tray loading/empty/error states** (Web Stories #11) | Lower user impact than the viewer itself. |
| **Tray viewed-ring not updated locally** (Web Stories #12) | Requires event plumbing; pick up after viewer reliability is solid. |
| **Video posts not playable in web feed** (Web Feed #17) | Needs backend MIME support and a `<video>` renderer; cross-platform media pipeline. |
| **Post media silent failure / retry** (Web Feed #18) | Partially mitigated by feed error state; full blob-media parity is larger. |
| **Like toggle can target wrong DOM card** (Web Feed #20) | Current `data-post-id` lookup is correct in practice; revisit if duplicate IDs appear. |
| **Comment input single-line / keyboard handling** (Web Comments #22) | Needs auto-growing textarea and `visualViewport` handling; larger than this sprint. |
| **Comments reload entirely after posting** (Web Comments #23) | Optimistic prepend is low risk but medium effort; defer. |
| **Composer caption shown for stories** (Web Composer #24) | Small, but less urgent than feed/story reliability. |
| **Client-side image compression in web composer** (Web Composer #25) | iOS already compresses; web can use canvas resize in a later pass. |
| **Camera defaults rear-facing** (Web Camera #26) | One-line change; batch with camera video work. |
| **Camera video max duration / WebM** (Web Camera #27) | Backend MP4 support and duration capping; medium effort. |
| **Deep links lost on login redirect** (Web Nav #29) | Small; defer until auth flow polish pass. |
| **Post detail back button exits app** (Web Nav #30) | Router-level change; defer to navigation polish. |
| **Active tab highlight wrong on non-tab routes** (Web Nav #31) | Cosmetic; defer. |
| **Icon buttons lack labels / SVGs not aria-hidden** (Web Nav #32) | Broad surface; defer to accessibility pass. |
| **Focus indicators insufficient** (Web Nav #33) | CSS-only; defer to accessibility pass. |
| **iOS logs out on network errors** (iOS #35) | `AuthManager` fix is small but risky; validate separately. |
| **Full feed reload on like/delete** (iOS #37) | Local mutation preferred; medium effort due to `Post` value-type updates. |
| **Create flow cannot post video to feed** (iOS #41) | Cross-platform media pipeline; large effort. |
| **Text composer placeholder** (iOS #42) | Small UI polish; defer. |

---

## Suggested Acceptance Criteria

- **Batch 1:** Web stories load via blob URLs; Safari/PWA no longer shows broken-image placeholders; left/right taps and swipe-to-close work without double advances; video audio stops when navigating away; video progress bar advances smoothly.
- **Batch 2:** Web feed load failures show a retry card instead of an infinite spinner; pull-to-refresh does not attach duplicate listeners; creating a post refreshes the feed; non-owner posts show a report action; offline state shows a banner.
- **Batch 3:** iOS notifications tab shows an unread badge; opening notifications clears the badge; home feed errors show a retry card instead of the empty-state illustration; like/comment/menu hit areas are ≥44×44 pt; story viewer bottom user info is visible and not covered by tap zones.
