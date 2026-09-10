# Roadmap и журнал работ

Цель первой версии — см. `Docs/product.md`. Архитектура — `Docs/intelligence.md`.
Статусы: ☐ не начато · ◐ в работе · ☑ сделано · ⚠ требует проверки на Mac.

## Этап 0. Инфраструктура (Linux) — ☑

- ☑ Бриф заказчика сохранён в `Docs/brief.md`.
- ☑ `Package.swift` (path `Linea/Core`, паритет настроек Xcode), `Tests/`,
  `Scripts/test-core.sh` (Docker, swift:6.3), `Scripts/check-layers.sh`,
  CI `core-linux.yml` (блокирующий) и `ios-macos.yml` (вручную).
- ☑ Перенос существующих моделей и протоколов в `Linea/Core`, реализаций —
  в `Linea/Data` (внутри synchronized group, pbxproj не тронут).

## Этап 1. Доменная модель ядра (Linux) — ☑

- ☑ `TimeContext`, `Signal`/`SignalKind`/`ProviderID`, `Commitment`,
  `ContextSnapshot`, `DailyHealthSummary`/`Baseline`/`SleepNight`,
  `UserProfile`, `NutritionProfile`/`MealLog`, `UserState`/`Fact`,
  `DayPlan`/`PlanBlock`/`Recommendation`, `Nudge`, `UserFeedback`,
  `Calibration`/`EngineConfig`, `DayRecord`.
- ☑ `LineaTask` += deadline, scheduledStart, estimatedMinutes,
  cognitiveDemand, goalID, completedAt; `LineaGoal` += horizon, startDate,
  isActive. Аддитивно, существующий UI компилируется без изменений.
- ☑ Протоколы: `ContextProvider`, `StateAnalyzer`, `PlanRule`, `NudgeRule`,
  `Explainer`/`TextRenderer`, репозитории, `HealthHistorySource`.
- ☑ `WowFixture` (сценарий брифа в числах), фейки, Codable round-trip,
  `Circadian`.

## Этап 2. Движки (Linux) — ◐

- ◐ State Engine: SleepAnalyzer, BaselineCalculator, анализаторы sleep /
  recovery / strain, EnergyFusion.
- ◐ Decision Engine: TaskScorer, FreeWindows, DayPlanner, LoadAdjustmentRule,
  NudgeEngine (BehindSchedule, EveningCheckIn), replan.
- ◐ Объяснения: RussianText, RuleBasedExplainer (golden-строки брифа),
  ExplanationValidator, FallbackExplainer.
- ◐ ContextEngine + CommitmentMapper, FeedbackEngine, коннектор Nutrition.
- ☐ Use cases: BuildDayPlan, AcceptPlan, CheckIn, RespondToNudge,
  RecordDayRating; SleepInsight для экрана Health; end-to-end тест
  wow-сценария (утро → 14:30 → вечер).

## Этап 3. Apple-слой (пишется на Linux, компилируется на Mac) — ☐ ⚠

- ☐ `TaskEntity`/`GoalEntity`: новые optional-поля (lightweight-миграция);
  `DayRecordEntity`, `CalibrationEntity`, `UserProfileEntity`,
  `NutritionProfileEntity`, `MealLogEntity`; `Local*Repository`;
  `ModelContainer` в `LineaApp`.
- ☐ `HealthKitManager+History` (28 дней: сегменты сна с источниками, HRV,
  RHR, шаги, энергия, тренировки) и `HealthKitContextProvider`;
  `healthStore` становится internal.
- ☐ `AppContainer` (composition root: провайдеры, анализаторы, правила,
  объяснитель, `TimeContext.live`), `IntelligenceStore` (view-facing).
- ☐ Редакторы: задача (дедлайн, время начала, длительность, сложность,
  цель), цель (горизонт, активность).
- ☐ Today: утренний бриф, «Принять план», тайм-блоки вместо демо-расписания,
  карточка нуджа, вечерняя оценка. Health: «Сон за 7/28 дней». Nutrition:
  профиль и «Поел». Profile: «Подключения», «AI», «Калибровка», «О себе».
- ☐ `Platform/NudgeScheduler` (UserNotifications с категориями действий),
  `Platform/FoundationModelsExplainer` за `#if canImport`.

## Этап 4. Проверка на Mac и приёмка — ☐ ⚠

Чек-лист (выполняет тот, у кого есть Xcode 26):
1. `xcodebuild -project Linea.xcodeproj -scheme Linea -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` — без ошибок.
2. `swift test` на macOS-тулчейне (Apple Foundation vs swift-corelibs).
3. Старая сборка с данными → новая: lightweight-миграция прошла, задачи/цели на месте.
4. HealthKit: тайлы совпадают с Health.app; «Сон» = ночь без двойного счёта; история 28 дней и baseline; отказ доступа → честный текст.
5. Утренний план на реальных данных: тексты, три действия, «Принять план», блоки без пересечений.
6. Нудж: задача не закрыта → карточка и уведомление с действиями; закрыть задачу → уведомление снято.
7. Вечерняя оценка → Profile «Калибровка» показывает изменения.
8. FoundationModels: доступность, русский текст, fallback без Apple Intelligence.
9. Xcode-навигатор: `Linea/Core`, `Data`, `Platform` видны; `Tests/` и `Package.swift` не в таргете.
10. Previews (`PlanStore.preview`, `RootView`) компилируются.

## v1.1 (после приёмки)

- Календарь (EventKit) по рецепту коннектора; перенос
  `HealthKitManager.swift` в `Linea/Data/HealthKit` (sed по строкам 10, 15,
  42, 128 pbxproj); `BGTaskScheduler` для уточнения нуджей; on-device
  подсказка «задача относится к цели X»; облачный объяснитель через
  бэкенд-прокси и `POST /v1/explain` в `API/openapi.yaml`.

## Журнал

- **2026-09-09.** Получен бриф. Изучен репозиторий: SwiftUI-приложение с
  SwiftData (задачи/цели), read-only HealthKit «за сегодня», без тестов и
  без Intelligence. Проверено: чистое Swift-ядро собирается и тестируется в
  Docker (Swift 6.3.3) с настройками, идентичными Xcode 26.6.
- **2026-09-10.** Проведён разбор архитектуры (четыре независимых
  проработки + критика брифа + судейство + синтез). Решения записаны в
  `Docs/decisions.md`. Реализованы этапы 0–1, спецификация
  `Docs/intelligence.md`, начат этап 2.
