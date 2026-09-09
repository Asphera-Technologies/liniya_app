# AI Agent Instructions for Linea

## General rules

- Study the existing implementation before changing code.
- Preserve the current architecture unless there is a clear reason to change it.
- Do not perform large refactors without a dedicated task.
- Do not change `Backend/` during iOS tasks unless explicitly requested.
- Do not change iOS code during backend tasks unless necessary.
- Treat `API/openapi.yaml` as the source of truth for iOS-backend communication.
- Never commit secrets, API keys, tokens, passwords, local `.env` files, or private credentials.
- Do not create mock or fake user data where the app expects real user data.
- Use existing components, repositories, stores, and design-system primitives before creating new ones.
- Do not push, merge, or rewrite Git history unless explicitly instructed.

## iOS project facts

- Language: Swift.
- UI: SwiftUI.
- App state: Observation with `@Observable` and SwiftUI environment injection.
- Persistence: SwiftData for local tasks and goals.
- Architecture: feature-oriented SwiftUI views, shared design-system/components, view-facing stores, domain models, repository protocols, and local repository implementations.
- Concurrency: Swift concurrency with async/await. Prefer async/await for new asynchronous work.
- Networking: `LineaBackend` currently exists as a sample-only protocol with `SampleBackend`. There is no production API client yet.
- Future backend requests should go through one networking layer/API client, not scattered `URLSession` calls across feature views.
- Apple frameworks currently used include SwiftUI, Foundation, Observation, SwiftData, and HealthKit.
- HealthKit access is centralized in `HealthKitManager` and is read-only.
- Deployment target: iOS 26.5.

## Before finishing each iOS task

1. Build the project.
2. Fix compilation errors.
3. Check warnings.
4. Check `git diff`.
5. List changed files.
6. State what still requires testing on a physical iPhone.
7. Do not merge by yourself.
