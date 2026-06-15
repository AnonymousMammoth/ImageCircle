# Agent Onboarding — PhotoCircle

This project is a private photo/video sharing app with:

- **iOS client**: `ImageCircle/` — SwiftUI/Swift, Xcode project `ImageCircle.xcodeproj`.
- **Active backend**: `Backend Infrastructure/project/` — Go + SQLite + Gin + vanilla JS web app in `web/`.
- **Docs**: `Documentation/` (start with `ARCHITECTURE.md` and `AGENT_ONBOARDING.md`).

## Quick commands

```bash
# iOS build
xcodebuild -project ImageCircle.xcodeproj -scheme ImageCircle \
  -destination "platform=iOS Simulator,name=iPhone 17,OS=26.1" \
  -skipMacroValidation -skipPackagePluginValidation \
  build CODE_SIGNING_ALLOWED=NO

# Backend build/test
cd "Backend Infrastructure/project"
make build
make test
make docker-up
```

## Conventions

- Keep changes minimal and match existing style.
- Go: `gofmt`, parameterized SQL (`?` placeholders), use `utils.Respond*` helpers.
- Swift: route networking through `APIClient`; use `AuthManager.canDelete(...)` for ownership/admin checks.
- Do not commit secrets, `.env`, or derived data.
- Update `Documentation/API_CONTRACT.md`, `BACKEND_NOTES.md`, `FRONTEND_NOTES.md`, `SECURITY.md`, and this file when contracts, env vars, or security controls change.

For the full guide, see [`Documentation/AGENT_ONBOARDING.md`](Documentation/AGENT_ONBOARDING.md).
