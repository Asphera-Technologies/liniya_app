# Linea

Linea is an iOS personal assistant that links Apple Health data, tasks, goals
and nutrition and answers one question: *what should I do next?* The
repository holds the iOS app, its Foundation-only intelligence core (built and
tested without Xcode), the API contract and the project documentation.

## Repository structure

- `Linea.xcodeproj` - Xcode project for the iOS app.
- `Linea/` - iOS source code and app resources (`Core/` is the Foundation-only
  intelligence core; `Data/` and `Platform/` are Apple adapters; `Features/` are screens).
- `HealthKitManager.swift` - read-only HealthKit boundary (kept at the root, see AGENTS.md).
- `Package.swift`, `Tests/`, `Scripts/` - SwiftPM manifest, tests and scripts for the core.
- `Backend/` - placeholder for the independently developed backend (not required for v1).
- `API/openapi.yaml` - source of truth for the API contract between backend and iOS.
- `Docs/` - product, architecture, intelligence specification, decisions, roadmap
  (start with `Docs/README.md`).
- `AGENTS.md` - persistent instructions for AI agents working in this repository.

## Opening the iOS project

Open `Linea.xcodeproj` in Xcode 26 and build the `Linea` scheme.
Step-by-step instructions for running it on an iPhone and what to look at:
`Docs/how-to-run.md` (in Russian).

## Testing the core without Xcode

```bash
Scripts/check-layers.sh   # layer lint
Scripts/test-core.sh      # swift test in Docker (swift:6.3)
```

The backend is not implemented yet. Do not add real secrets to the repository;
use local `.env` files based on `Backend/.env.example`.
