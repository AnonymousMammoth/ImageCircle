# iOS Frontend Notes — ImageCircle

## Architecture

The iOS app is a single-target SwiftUI project. State is held in a small number of `@MainActor` singletons and observed by views.

### Key Classes

| File | Role |
|------|------|
| `ImageCircleApp.swift` | App entry point. Restores the Keychain token on launch and routes to `LoginView` or `MainTabView`. |
| `Services/AuthManager.swift` | Central auth state (`token`, `currentUser`, `isAuthenticated`). Handles login, logout, password change, and token refresh. |
| `Services/APIClient.swift` | URLSession-based backend client. All endpoints assume `/api` prefix. Handles JSON encoding/decoding and multipart uploads. |
| `Services/KeychainHelper.swift` | Stores the JWT in the iOS Keychain. |
| `Models/Post.swift` | Feed post model. Uses explicit `CodingKeys` for snake_case backend fields. |
| `Models/User.swift` | User model. |
| `Models/Comment.swift` | Comment model. |
| `Models/Story.swift` | Story model with `isImage` / `isVideo` helpers. |
| `Models/FeedFilter.swift` | Client-side filter for `Mixed`, `Images`, `Text`. |
| `Views/MainTabView.swift` | Root tab interface. Admin tab is shown only when `auth.isAdmin` is true. |

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

`APIClient.token` is set by `AuthManager` after login and on app launch.

### Media Display

- **Images**: loaded and cached with [Kingfisher](https://github.com/onevcat/Kingfisher) (`KFImage`).
- **Video**: played with `AVPlayer` / `VideoPlayer` (e.g., story viewer and preview).
- **Media URLs**: built by `MediaURL.url(userID:filename:)` in `Utilities/ViewExtensions.swift` as `{server_url}/media/{user_id}/{filename}`.

## Screens and Where to Find Them

| Screen | File | Notes |
|--------|------|-------|
| Login | `Views/Login/LoginView.swift` | Server URL, username, password. |
| Force password change | `Views/Login/ForcePasswordChangeView.swift` | Non-dismissible cover after first login with temp password. |
| Home / feed | `Views/Home/HomeView.swift` | Stories tray, post list, feed filter, comments sheet. |
| Post card | `Views/Home/PostCardView.swift` | Header, image or text body, like/comment actions. |
| Stories tray | `Views/Home/StoriesTrayView.swift` | Horizontal circles; deduplicates by user. |
| Story viewer | `Views/Home/StoryViewerView.swift` | Full-screen story viewer with progress bars, tap zones, auto-advance, video support. |
| Camera / create | `Views/Camera/CameraView.swift` | Photo/video/text capture mode picker. |
| Media preview | `Views/Camera/MediaPreviewView.swift` | Preview, compression, and upload to feed or story. |
| Text composer | `Views/Camera/TextPostComposerView.swift` | Twitter-style text-only composer. |
| Profile | `Views/Profile/ProfileView.swift` | Header, stats, post grid. Currently filters the feed for the current user. |
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

## Compression

Media is compressed client-side before upload:

- **Photos** (`MediaPreviewView.compressPhoto(_:)`): resized so the longest edge is ≤ 2048 px, JPEG quality 0.85, which strips metadata.
- **Videos** (`MediaPreviewView.compressVideo(_:)`): re-exported to H.264/AAC MP4 at 1080p max.
- **Thumbnails** (`generateThumbnail(for:)`): JPEG at 1-second mark, max 512 px edge.

## Known Issues to Watch

1. **API path mismatches.** `APIClient` uses several paths that do not match the current backend (e.g., `/api/me`, `/api/feed`, `/api/admin/users`, `/api/users/search`). See [`API_CONTRACT.md`](API_CONTRACT.md) § Known iOS ↔ Backend Mismatches.
2. **Multipart field name.** `APIClient.createPost` and `createStory` use field name `file`; the backend expects `media`.
3. **Text-only posts not wired up.** `createTextPost(caption:)` sends JSON, but the backend requires multipart media.
4. **Unlike uses DELETE.** `APIClient.unlikePost` calls `DELETE /api/posts/:id/like`, but the backend only implements a toggle via `POST`.
5. **Profile posts are feed-filtered.** There is no backend endpoint for a specific user’s posts.

When you change any iOS network code, always verify it against the current backend routes in `Backend Infrastructure/project/cmd/server/main.go`.
