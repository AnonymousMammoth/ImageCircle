# Circle / ImageCircle Documentation

This folder contains the canonical guides for the Circle private photo/video sharing project. Everything here is derived from the actual source code in `/Users/mattmarsh/Documents/PhotoCircle`; if the code changes, these docs should be updated to match.

## Documentation Index

| File | What it covers | Read this when… |
|------|----------------|-----------------|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | High-level system overview, components, data flow, auth, and security highlights. | You are new to the project. |
| [`API_CONTRACT.md`](API_CONTRACT.md) | Canonical backend API routes, request/response shapes, multipart field names, iOS model mappings, and first-admin setup. | You are integrating a client, writing a new endpoint, or debugging the iOS ↔ backend contract. |
| [`AGENT_ONBOARDING.md`](AGENT_ONBOARDING.md) | Directory layout, how to build/test, coding conventions, common pitfalls, and how to keep docs in sync. | You are about to write or modify code. |
| [`SECURITY.md`](SECURITY.md) | Security controls from the backend audit, mobile-specific notes, and deployment hardening checklist. | You are deploying, reviewing security, or changing auth/media handling. |
| [`FRONTEND_NOTES.md`](FRONTEND_NOTES.md) | iOS SwiftUI architecture, key classes/views, and client-side behavior (feed filter, media display). | You are working on the iOS app. |
| [`BACKEND_NOTES.md`](BACKEND_NOTES.md) | Go backend stack, middleware order, handler responsibilities, storage layout, env vars, and Docker/nginx wiring. | You are working on the Go backend. |

## Where to Start

1. **New agent?** Read [`ARCHITECTURE.md`](ARCHITECTURE.md) first, then [`AGENT_ONBOARDING.md`](AGENT_ONBOARDING.md).
2. **Changing an API?** Update [`API_CONTRACT.md`](API_CONTRACT.md) and check the iOS mappings section.
3. **iOS work?** Read [`FRONTEND_NOTES.md`](FRONTEND_NOTES.md) and the iOS mappings in [`API_CONTRACT.md`](API_CONTRACT.md).
4. **Backend work?** Read [`BACKEND_NOTES.md`](BACKEND_NOTES.md) and [`SECURITY.md`](SECURITY.md).
5. **Deploying?** Follow [`SECURITY.md`](SECURITY.md) § Deployment Hardening Checklist.

## Important Note

These documents describe the code as it exists today. Where the iOS client and backend are currently out of sync, the docs call it out explicitly (the biggest example is the iOS upload field name and a few iOS route paths). Always trust the source files over stale documentation.
