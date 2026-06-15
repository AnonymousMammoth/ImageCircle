# iOS Frontend Notes — ImageCircle

## Architecture

The iOS app is a single-target SwiftUI project. State is held in a small number of `@MainActor` singletons and observed by views.

### Key Classes

| File | Role |
|------|------|
| `ImageCircleApp.swift` | App entry point. Restores the Keychain token on launch and routes to `LoginView` or `MainTabView`. |
| `Services/AuthManager.swift` | Central auth state (`token`, `currentUser`, `isAuthenticated`). Handles login, logout, password change, and token refresh. Exposes `canDelete(contentUserID:)` so admins can delete others' content. |
| `Services/APIClient.swift` | URLSession-based backend client. All endpoints assume `/api` prefix. Handles JSON encoding/decoding and multipart uploads. Uses `HTTPCookieStorage.shared` so the backend `circle_session` cookie is sent with media requests. |
| `Services/KeychainHelper.swift` | Stores the JWT in the iOS Keychain. |
| `Models/Post.swift` | Feed post model. Uses explicit `CodingKeys` for snake_case backend fields. |
| `Models/User.swift` | User model. |
| `Models/Comment.swift` | Comment model. |
| `Models/Story.swift` | Story model with `isImage` / `isVideo` helpers. |
| `Models/FeedFilter.swift` | Client-side filter for `Mixed`, `Images`, `Text`. |
| `Models/AppNotification.swift` | In-app notification model returned by `GET /api/notifications`. |
| `Views/MainTabView.swift` | Root tab interface: Home, Search, Create, Notifications, Profile, and an Admin tab shown only when `auth.isAdmin` is true. |
| `Views/Camera/CreateComposerView.swift` | Entry point for create flow (camera/library/text). |

### Networking

`APIClient` configures a `JSONDecoder` with:

```swift
decoder.keyDecodingStrategy = .convertFromSnakeCase
decoder.dateDecodingStrategy = .iso8601
```

and a matching `JSONEncoder`. Despite the global strategy, models still declare explicit `CodingKeys` for fields that benefit from clarity (e.g., `likesCount = "likes_count"`).

Two `URLSession`s are used:

- `session`: 30s request / 60s resource timeout for normal calls.
- `uploadSession`: 120s request / 300s resource timeout for uploads.

Both sessions use `HTTPCookieStorage.shared` and `httpShouldSetCookies = true` so the backend `circle_session` cookie is automatically stored and sent back. This is important for authenticated `<img>` and video requests (`KFImage`, `VideoPlayer`) that cannot send a custom `Authorization` header.

`APIClient.token` is set by `AuthManager` after login and on app launch.

### Media Display

- **Images**: loaded and cached with [Kingfisher](https://github.com/onevcat/Kingfisher) (`KFImage`).
- **Video**: played with `AVPlayer` / `VideoPlayer` (e.g., story viewer and preview).
- **Media URLs**: built by `MediaURL.url(userID:filename:)` in `Utilities/ViewExtensions.swift` as `{server_url}/media/{user_id}/{filename}`.
- **Auth**: media requests rely on the shared `circle_session` cookie. The iOS URLSession cookie storage is enabled for both the normal and upload sessions.

## Screens and Where to Find Them

| Screen | File | Notes |
|--------|------|-------|
| Login | `Views/Login/LoginView.swift` | Server URL, username, password. |
| Force password change | `Views/Login/ForcePasswordChangeView.swift` | Non-dismissible cover after first login with temp password. |
| Home / feed | `Views/Home/HomeView.swift` | Stories tray, post list, feed filter, comments sheet. |
| Post card | `Views/Home/PostCardView.swift` | Header, image or text body, like/comment actions. |
| Stories tray | `Views/Home/StoriesTrayView.swift` | Horizontal circles; deduplicates by user. |
| Story viewer | `Views/Home/StoryViewerView.swift` | Full-screen story viewer with progress bars, tap zones, auto-advance, video support. |
| Notifications | `Views/Notifications/NotificationsView.swift` | Likes and comments on the current user's posts; tapping a notification opens the post. |
| Create composer | `Views/Camera/CreateComposerView.swift` | Entry picker for camera, library, or text-only post. |
| Camera / capture | `Views/Camera/CameraView.swift` | Tap the shutter for a photo, hold for video (up to 30s). Includes library picker. |
| Media preview | `Views/Camera/MediaPreviewView.swift` | Preview, compression, and upload to feed or story. |
| Text composer | `Views/Camera/TextPostComposerView.swift` | Twitter-style text-only composer. |
| Profile | `Views/Profile/ProfileView.swift` | Header, avatar upload, stats, post grid. Uses `GET /api/users/:id/posts` with a feed fallback. |
| Settings | `Views/Profile/SettingsView.swift` | Change password, admin panel link, logout + cache clear. |
| Change password | `Views/Profile/ChangePasswordView.swift` | Self-service password change. |
| Search | `Views/Search/SearchView.swift` | Debounced username search. |
| Admin panel | `Views/Admin/AdminView.swift` | Admin-only user CRUD with temporary passwords. |

## Feed Filter

The home feed filter is implemented entirely on the client:

```swift
enum FeedFilter: String, CaseIterable, Identifiable {
    case mixed = "Mixed"
    case images = "Images"
    case text = "Text"

    func includes(_ post: Post) -> Bool {
        switch self {
        case .mixed: return true
        case .images: return !post.isTextOnly
        case .text: return post.isTextOnly
        }
    }
}
```

`HomeView` fetches the full feed via `APIClient.fetchFeed()` and then filters it:

```swift
private var filteredPosts: [Post] {
    posts.filter { feedFilter.includes($0) }
}
```

There is no backend `?type=` parameter yet. If one is added later, move the filtering to `APIClient.fetchFeed(filter:)` and remove the local filter.

## Camera Interactions

`CameraView` uses a single shutter control with a long-press gesture:

- **Tap** the shutter circle to take a photo.
- **Hold** the shutter circle to start recording video; release to stop.
- A pending photo capture is scheduled on touch down and cancelled if the long-press threshold is reached, so holding does not also trigger a photo.
- Recording is capped at 30 seconds and shows a red progress ring.

## Compression

Media is compressed client-side before upload:

- **Photos** (`MediaPreviewView.compressPhoto(_:)`): resized so the longest edge is ≤ 2048 px, JPEG quality 0.85, which strips metadata.
- **Videos** (`MediaPreviewView.compressVideo(_:)`): re-exported to H.264/AAC MP4 at 1080p max.
- **Thumbnails** (`generateThumbnail(for:)`): JPEG at 1-second mark, max 512 px edge.
- **Avatars** (`ProfileView.compressImageForAvatar(_:)`): resized to ≤ 1024 px, JPEG quality 0.85, compressed off the main actor.

## Branding

- **App icon**: red circle with "IC" monogram (`Assets.xcassets/AppIcon.appiconset`).
- **Launch screen**: `LaunchScreen.storyboard` with a red circle + "ImageCircle" label.

## Performance & Navigation Notes

Recent fixes removed the tab-navigation freeze that occurred when selecting the Create tab:

- Photo Library work is dispatched off the main thread.
- Image loading is cached via Kingfisher.
- Auth observation was fixed so tab state updates do not deadlock or stall the UI.

On the web app side (see `Backend Infrastructure/project/web/js/router.js`), fast navigation is handled with mount tokens and route debouncing to prevent components from rendering stale state.

## Admin Delete Permissions

`AuthManager.canDelete(contentUserID:)` returns `true` for the content owner **or** an admin. This is used in:

- `PostCardView` / `ProfilePostDetailView` — delete posts.
- `StoryViewerView` — delete stories (including other users' stories for admins).
- Comments sheet — delete comments.

## Known Issues to Watch

The major iOS/backend contract mismatches from earlier passes have been resolved (feed path, current-user path, admin paths, multipart field name, like toggle, and text-only posts). When you change any iOS network code, always verify it against the current backend routes in `Backend Infrastructure/project/cmd/server/main.go`.

1. **Profile loads posts from the dedicated user endpoint.** `ProfileView` calls `APIClient.fetchUserPosts(userID:)` (`GET /api/users/:id/posts`) and falls back to filtering the global feed for older backends.
2. **Camera permission errors.** If `AVCaptureDevice` authorization is denied, `CameraView` shows a permission placeholder with an Open Settings button.
