# PhotoCircle Deep UI/UX & Reliability Audit

Follow-up audit focusing on UI polish, reliability, and web stories.

---

## Web Stories (highest priority — reported unreliable)

1. **Story media not authenticated** (`storyViewer.js:278-331`)
   - Direct `<img>`/`<video>` src fails in Safari/PWA where cookie not sent for subresources.
   - Fix: fetch blobs with auth like avatars.

2. **Duplicate touch/pointer handlers** (`storyViewer.js:106-188`)
   - Both touch and pointer events fire, causing double advances / stuck pause.
   - Fix: use pointer events only.

3. **Old video keeps playing after navigation** (`storyViewer.js:270-334`)
   - Detached video element can continue audio.
   - Fix: pause and clear src before replacing.

4. **No media preloading** (`storyViewer.js:210-334`)
   - Each story fetched only when displayed.
   - Fix: preload next 1-2 stories as blobs.

5. **Video progress bar never advances** (`storyViewer.js:285-320`, `353-365`)
   - No `timeupdate` listener.
   - Fix: map video currentTime to progress bar.

6. **Image timer starts before image loads** (`storyViewer.js:223-228`, `320-328`)
   - Progress bar fills while still loading.
   - Fix: start timer in image `onload`.

7. **Progress bars rebuilt every 50ms** (`storyViewer.js:336-351`)
   - Causes layout thrash.
   - Fix: create once, update widths.

8. **State not reset on open/close** (`storyViewer.js:22-32`, `457-464`)
   - `isPaused`/`dragOffset` can persist.
   - Fix: reset in open/close.

9. **Long-press pause triggers tap navigation on release** (`storyViewer.js:95-191`)
   - Fix: suppress tap if long-press fired.

10. **No loading placeholder** (`storyViewer.js:270-333`)
    - Fix: show spinner until media ready.

11. **Story tray no loading/empty/error states** (`storiesTray.js`)
    - Fix: add spinner / empty label.

12. **Tray viewed-ring not updated locally** (`storyViewer.js:412-421`, `home.js:24-31`)
    - Fix: mark local story viewed and emit refresh event.

---

## Web Feed / Posts

13. **Feed load errors silent** (`home.js:210-212`)
    - Fix: error message + retry button.

14. **Pull-to-refresh listener leaks / duplicates** (`home.js:42-57`)
    - Fix: attach once or remove before re-adding.

15. **New posts don't appear after creation** (`composer.js:186-207`)
    - Fix: set `homeComponent.hasLoaded = false` before navigating home.

16. **Load-more failure can loop** (`home.js:247-254`)
    - Fix: stop observing sentinel or set hasMore false on error.

17. **Video posts not playable** (`postCard.js:57-74`)
    - Always renders `<img>`; videos fail.
    - Fix: detect video and render `<video>`.

18. **Post media fails silently** (`postCard.js:60-61`)
    - `onerror` hides image.
    - Fix: placeholder + retry, or authenticated blob.

19. **Post cards lack report action** (`postCard.js:47-52`)
    - iOS has report; web doesn't.
    - Fix: add report menu item.

20. **Like toggle can target wrong DOM card** (`postCard.js:131-161`)
    - Fix: keep button reference or re-render via callback.

21. **Post action touch targets too small** (`app.css:532-551`)
    - Fix: min 44x44.

---

## Web Comments / Composer / Camera

22. **Comment input single-line / hidden by keyboard** (`comments.js:40-44`, `app.css:1195-1206`)
    - Fix: auto-growing textarea, visualViewport handling.

23. **Comments reload entirely after posting** (`comments.js:150-165`)
    - Fix: optimistic prepend + background refresh.

24. **Composer caption shown for stories (ignored)** (`composer.js:90-106`)
    - Fix: hide/disable caption for stories.

25. **No client-side image compression** (`composer.js:160-178`, `camera.js:137-150`)
    - Fix: canvas resize to max 2048.

26. **Camera defaults rear-facing** (`camera.js:79-80`)
    - Fix: default `user`.

27. **Camera video no max duration / WebM rejected by backend** (`camera.js:153-217`)
    - Fix: 30s cap; remove WebM fallback or support it backend.

28. **Composer text post no loading state** (`composer.js:152-154`)
    - Fix: disable button, show spinner.

---

## Web Navigation / Accessibility

29. **Deep links lost on login redirect** (`app.js:99-104`)
    - Fix: save redirect param.

30. **Post detail back button exits app** (`postDetail.js:21-22`)
    - Fix: navigate home if history length <= 1.

31. **Active tab highlight wrong on non-tab routes** (`shell.js:185-193`)
    - Fix: return null and clear active state.

32. **Icon buttons lack labels / SVGs not aria-hidden** (multiple)
    - Fix: add aria-label, aria-hidden.

33. **Focus indicators insufficient** (`app.css:135-150`)
    - Fix: `:focus-visible` outline.

34. **No offline indicator** (`sw.js`, `app.js`)
    - Fix: online/offline banner.

---

## iOS

35. **Logs out on network errors** (`AuthManager.swift:39-54`)
    - Fix: only logout on 401.

36. **Home feed errors show misleading empty state** (`HomeView.swift:55-57`, `138-163`)
    - Fix: error + retry.

37. **Full feed reload on like/delete** (`HomeView.swift:61,63`, `PostCardView.swift:287`)
    - Fix: mutate local posts.

38. **No notification badge/mark-read** (`MainTabView.swift:44-49`, `NotificationsView.swift`)
    - Fix: fetch unread count, badge, call mark-read.

39. **Post-card touch targets too small** (`PostCardView.swift:125-129`, `195-211`)
    - Fix: 44x44.

40. **Story viewer tap zones cover bottom user info** (`StoryViewerView.swift:220-223`, `296-314`)
    - Fix: reorder overlays.

41. **Create flow cannot post video to feed** (`CreateComposerView.swift:77-87`, `MediaPreviewView.swift:131-142`)
    - Fix: open full camera, add post-video action.

42. **Text composer no placeholder** (`CreateComposerView.swift:171-208`)
    - Fix: placeholder label.

---

## Top Quick Wins

1. Fix web story media authentication (blob fetch).
2. Remove duplicate touch/pointer handlers in story viewer.
3. Pause old story video before replacing.
4. Add loading placeholder and start timer on media load.
5. Fix web feed pull-to-refresh listener leak.
6. Show error + retry on web feed load failure.
7. Refresh web feed after creating a post.
8. Add iOS notification badge and mark-read parity.
9. Increase post action touch targets (web + iOS).
10. Add report actions to web posts/stories.
