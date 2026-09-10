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

## Этап 2. Движки (Linux) — ☑

- ☑ State Engine: SleepAnalyzer (дедупликация источников), BaselineCalculator
  (медиана/MAD, полы, окно 28 дней), анализаторы sleep / recovery / strain,
  EnergyFusion с гистерезисом; покрыт тестами (55 тестов ядра зелёные).
- ☑ Аналитика сна (`SleepInsight`) для экрана Health.
- ☑ Подсказка связи задачи с целью (`KeywordGoalMatcher`).
- ☑ Decision Engine: TaskScorer, FreeWindows, DayPlanner, правила
  (DayBrief, LoadAdjustment), NudgeEngine (BehindSchedule, EveningCheckIn),
  пересборка плана.
- ☑ Объяснения: RussianText, RuleBasedExplainer (golden-строки брифа слово в
  слово), ExplanationValidator, FallbackExplainer.
- ☑ ContextEngine + CommitmentMapper, FeedbackEngine, коннектор Nutrition
  (провайдер окон еды, правило обеда и перекуса, компонент «топливо»).
- ☑ Use cases: PlanDay, AcceptPlan, CheckIn, RespondToNudge, RecordDayRating;
  сквозной тест wow-сценария (утро → 14:30 → вечер) и деградации без данных.
- ☑ 162 теста ядра зелёные в Docker, включая первый запуск без данных,
  пустой день, поздний вечер, просроченные задачи и смену часового пояса.

## Этап 3. Apple-слой (пишется на Linux, компилируется на Mac) — ◐ ⚠

- ☑ `TaskEntity`/`GoalEntity`: новые optional-поля (lightweight-миграция);
  `DayRecordEntity`, `DocumentEntity` (калибровка, профиль, питание),
  `MealLogEntity`; `Local*Repository`; общая схема `LineaSchema`.
- ☑ `HealthKitHistoryReader` (28 дней: сегменты сна с источниками, HRV,
  RHR, шаги, энергия, тренировки) и `HealthKitContextProvider`;
  тайл сна в `HealthKitManager` переведён на `SleepAnalyzer`.
- ☑ `AppContainer` (репозитории, хранилища, провайдеры, `TimeContext.live`).
- ☑ `IntelligenceStore` (состояние, план, нуджи, калибровка, ответы AI-экрана)
  и подписка на изменения задач, целей, профиля и питания.
- ☑ Редакторы: задача (дедлайн, время начала, длительность, сложность,
  цель + подсказка), цель (горизонт, активность), питание (профиль,
  окна еды, «Поел»), «О себе» (рабочий день, тихие часы, сон).
- ☑ Today: утренний бриф, «Принять план», тайм-блоки, карточка нуджа,
  вечерняя оценка, советы по питанию. Health: «Сон за 7 дней» с графиком
  против личной нормы. Nutrition: профиль и «Поел». Profile: «Подключения»,
  «AI», «Калибровка», «О себе». Демо-данные удалены.
- ☑ `Platform/NudgeScheduler` (UserNotifications с категориями действий) и
  `AppDelegate` для ответов на уведомления.
- ☐ `Platform/FoundationModelsExplainer` (on-device модель iOS 26) — **не
  начат осознанно**: API нельзя проверить без Mac, а ошибка в нём уронит
  сборку целиком. Точка подключения готова:
  `FallbackExplainer(primary:)` в `AppContainer`; сегодня передаётся `nil`,
  и приложение работает на шаблонах.

## Этап 4. Сборка на macOS-раннере — ☑

Выбранный путь: GitHub Actions, воркфлоу `.github/workflows/ios-macos.yml`.
Он запускается на push в `main`, на пул-реквестах и вручную; при провале
кладёт список ошибок компиляции в summary и полный лог в артефакты, чтобы
их можно было чинить без Mac.

Подготовлено:
- ☑ общая схема `Linea.xcodeproj/xcshareddata/xcschemes/Linea.xcscheme`
  (без неё `xcodebuild -scheme Linea` на CI падает: локальная схема лежит в
  `xcuserdata` и не коммитится);
- ☑ шаг диагностики: печатает доступные Xcode и выбирает 26-й, иначе самый
  новый с предупреждением;
- ☑ `swift test` на Apple-тулчейне — ловит расхождения Foundation.

**Готово.** Ветка `feature/ios-intelligence-core` собирается на GitHub
Actions: `** BUILD SUCCEEDED **`, предупреждений в коде Linea нет, и те же
162 теста ядра проходят ещё раз на Apple-тулчейне (Xcode 26.6).

Что чинилось по дороге:
1. **Изоляция репозиториев.** Протоколы были `nonisolated ... : Sendable`,
   из-за чего их требования становились неизолированными и реализации на
   `@MainActor` теряли доступ к собственному `ModelContext`. Протоколы
   репозиториев теперь привязаны к главному актору — там, где и живут их
   реализации на SwiftData. `ContextProvider` и `HealthHistorySource`
   остались `nonisolated Sendable`: они действительно неизолированные.
2. **Имена тренировок.** `HKWorkoutActivityType.displayName` читался из
   неизолированного контекста; помечен `nonisolated` (иначе ошибка в
   языковом режиме Swift 6).
3. **Лишний `nonisolated(unsafe)`** на `HKHealthStore`, который и так
   `Sendable`.

Раннер: метка `macos-26` не существует, задание идёт на `macos-15` с
Xcode 26.6 — шаг «Toolchain» сам выбирает самый новый Xcode и пишет об этом
предупреждение.

## Этап 5. Проверка на устройстве и приёмка — ☐ ⚠

Чек-лист (выполняет тот, у кого есть iPhone с данными):
1. `xcodebuild -project Linea.xcodeproj -scheme Linea -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` — без ошибок.
2. `swift test` на macOS-тулчейне (Apple Foundation vs swift-corelibs).
3. Старая сборка с данными → новая: lightweight-миграция прошла, задачи/цели на месте.
4. HealthKit: тайлы совпадают с Health.app; «Сон» = ночь без двойного счёта; история 28 дней и baseline; отказ доступа → честный текст.
5. Утренний план на реальных данных: тексты, три действия, «Принять план», блоки без пересечений.
6. Нудж: задача не закрыта → карточка и уведомление с действиями; закрыть задачу → уведомление снято.
7. Вечерняя оценка → Profile «Калибровка» показывает изменения.
8. Уведомления: разрешение запрашивается при первом «Принять план», кнопки «Закрываем сейчас» / «Переносим» доходят до приложения, выполненная задача снимает уведомление.
9. Xcode-навигатор: `Linea/Core`, `Data`, `Platform` видны; `Tests/` и `Package.swift` не в таргете.
10. Previews (`PlanStore.preview`, `RootView`) компилируются.
11. Экран «Питание»: редактор профиля, чипы, «Поел» — и обед появляется в плане дня.
12. Экран «Профиль» → «Калибровка»: после вечерней оценки значения меняются.

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
  `Docs/intelligence.md`, рецепт `Docs/connectors.md`.
- **2026-09-10.** Приложение впервые собралось: iOS-таргет и тесты ядра
  зелёные на macOS-раннере GitHub Actions. Причина падений — изоляция
  акторов у протоколов репозиториев; воспроизведена локально в Docker и
  исправлена. Дальше — запуск на реальном iPhone.
- **2026-09-10.** Ядро закончено: Decision Engine (scoring, свободные окна,
  расстановка блоков, ограничение нагрузки, пересборка), Nudge Engine,
  объяснения с golden-строками брифа, валидатор текста от модели, Feedback
  Engine, коннектор питания, use case'ы и сквозной тест wow-сценария.
  153 теста в Docker. Собран Apple-слой: экраны Today, Health, Nutrition,
  Profile, хранилище Intelligence, уведомления с кнопками. Осталось: сборка на
  Mac по чек-листу и on-device модель.
- **2026-09-10.** Готов State Engine и его тесты (55 тестов ядра зелёные в
  Docker). Опорные числа wow-сценария: energy 0.396, сон 0.674, восстановление
  0.04, вердикт «снизить нагрузку». Написан Apple-слой: персистентность
  документами, чтение истории HealthKit, композиционный корень, редакторы
  задачи/цели/питания/профиля. Всё, что импортирует SwiftUI, SwiftData или
  HealthKit, ждёт сборки на Mac.
