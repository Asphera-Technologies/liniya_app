# AI Agent Instructions for Linea

## General rules

- Study the existing implementation before changing code. Read `Docs/README.md`
  for the reading order; `Docs/intelligence.md` is the specification of the core.
- Preserve the current architecture unless there is a clear reason to change it;
  record architectural decisions in `Docs/decisions.md`.
- Do not perform large refactors without a dedicated task.
- Do not change `Backend/` during iOS tasks unless explicitly requested.
- Do not change iOS code during backend tasks unless necessary.
- Treat `API/openapi.yaml` as the source of truth for iOS-backend communication.
- Never commit secrets, API keys, tokens, passwords, local `.env` files, or private credentials.
- Do not create mock or fake user data where the app expects real user data.
  Test fixtures live only in `Tests/`; a debug-only demo provider must be `#if DEBUG`.
- Use existing components, repositories, stores, and design-system primitives before creating new ones.
- Do not push, merge, or rewrite Git history unless explicitly instructed.
- Commits: one-line conventional commits (`feat:`, `fix:`, `refactor:`, `docs:`, `build:`, `test:`), no trailers.
- Keep `Docs/roadmap.md` (status, journal) and `Docs/open-questions.md` up to date as work progresses.

## iOS project facts

- Language: Swift. UI: SwiftUI. App state: Observation with `@Observable` and environment injection.
- Persistence: SwiftData for local tasks, goals and intelligence documents (JSON blobs).
- Architecture: feature-oriented SwiftUI views, shared design-system/components, view-facing stores,
  a Foundation-only core (`Linea/Core`: domain models, protocols, use cases, engines) and Apple adapters
  (`Linea/Data`, `Linea/Platform`). See `Docs/architecture.md` for the dependency rules.
- Concurrency: Swift concurrency with async/await. The project uses
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: every type and protocol in `Linea/Core` must be
  declared `nonisolated` and be `Sendable`; stores and `Local*Repository` stay `@MainActor`.
- Time: engines never call `Date()`, `Calendar.current`, `TimeZone.current`, `Locale.current` —
  they take a `TimeContext`. `TimeContext.live` exists only in the composition root.
- Networking: `LineaBackend` is a sample-only protocol with `SampleBackend`. No production API client yet.
  Future backend requests go through one networking layer/API client.
- Apple frameworks in use: SwiftUI, Foundation, Observation, SwiftData, HealthKit (read-only, centralized
  in `HealthKitManager`), later UserNotifications and FoundationModels in `Linea/Platform`.
- `HealthKitManager.swift` stays at the repository root (explicitly referenced in project.pbxproj).
  Extend it with extension files under `Linea/Data/HealthKit`; do not move it without Xcode.
- Xcode uses a synchronized root group for `Linea/`: any file under `Linea/` is compiled into the app.
  Therefore tests live in `Tests/` at the repository root, never inside `Linea/`.
- Deployment target: iOS 26.5. Xcode 26.6 / Swift 6.3.

## Building and testing the core without Xcode

- `Scripts/test-core.sh` builds and tests `Linea/Core` in Docker (`swift:6.3`); `--filter <Suite>` narrows.
- `Scripts/check-layers.sh` lints layer boundaries; both must be green before finishing a core task.
- Anything that imports SwiftUI/SwiftData/HealthKit can only be verified on a Mac; list such changes
  explicitly when finishing a task.

## Before finishing each iOS task

1. Run `Scripts/check-layers.sh` and `Scripts/test-core.sh` (green).
2. Build the project in Xcode when a Mac is available; fix compilation errors; check warnings.
3. Check `git diff`.
4. List changed files.
5. State what still requires building on a Mac and testing on a physical iPhone.
6. Do not merge by yourself.
