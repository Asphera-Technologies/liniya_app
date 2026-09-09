# Linea

Linea is an iOS application with a repository structure prepared for parallel iOS, backend, and API contract development.

## Repository structure

- `Linea.xcodeproj` - Xcode project for the iOS app.
- `Linea/` - iOS source code and app resources.
- `Backend/` - placeholder for the independently developed backend.
- `API/openapi.yaml` - source of truth for the API contract between backend and iOS.
- `Docs/architecture.md` - current and target architecture notes.
- `Docs/development.md` - team development workflow.
- `AGENTS.md` - persistent instructions for AI agents working in this repository.

## Opening the iOS project

Open `Linea.xcodeproj` in Xcode and build the `Linea` scheme.

The backend is not implemented yet. Do not add real secrets to the repository; use local `.env` files based on `Backend/.env.example`.
