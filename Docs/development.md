# Development Workflow

## Team workflow

```text
Issue
  ↓
feature branch
  ↓
implementation
  ↓
Pull Request
  ↓
review
  ↓
merge into main
```

`main` must contain only a working project state.

## Branch naming

Use focused branches:

- `feature/ios-...`
- `feature/backend-...`
- `fix/ios-...`
- `fix/backend-...`

Do not merge directly into `main` without review.

## Areas of ownership

iOS work should stay in the existing Xcode project and Swift source tree unless a task explicitly requires repository-level changes.

Backend work should stay in `Backend/` unless a task explicitly requires API contract or documentation changes.

API contract changes belong in `API/openapi.yaml` and should be reviewed by both iOS and backend developers before implementation depends on them.

Do not commit secrets, local `.env` files, personal Xcode user data, build products, or generated caches.
