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

## UI-тесты на симуляторе

Экраны можно проверить без Mac. Сценарий `.github/workflows/ios-ui.yml`
собирает приложение, поднимает симулятор iPhone и запускает UI-тесты из
`Tests/LineaUITests` (схема `LineaUITests`). Тесты жмут кнопки, вводят текст,
открывают меню и поповеры, а на каждом шаге оставляют скриншот. Скриншоты
выгружаются артефактом `ui-screenshots`:

```bash
gh run list --workflow ios-ui.yml --limit 1
gh run download <id> -n ui-screenshots
```

Сценарий запускается на изменения экранов (`Linea/Features`,
`Linea/Components`, `Linea/App`) и самих тестов в feature-ветках. Прогон
длится около 20 минут macOS-раннера.

Приложение стартует с `-uiTesting` (только DEBUG): SwiftData в памяти, каждый
тест с чистого листа, данные вводятся через интерфейс, как человек. Часовой
пояс тест выбирает сам — такой, где сейчас около 11 утра. Так рабочий день
идёт при любом часе запуска. На Mac те же тесты запускаются через ⌘U на схеме
`LineaUITests`.

Чего так не проверить: голос (в симуляторе нет микрофона и модели), данные
Apple Health, уведомления. Это остаётся проверке на телефоне.
