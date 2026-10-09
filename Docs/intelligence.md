# Intelligence-ядро Linea: спецификация

Статус: рабочая спецификация v1 (2026-09-10). Источник решений — бриф
(`Docs/brief.md`), разбор четырёх независимых архитектурных предложений и
судейство (см. `Docs/decisions.md`). Код ядра лежит в `Linea/Core`, тесты — в
`Tests/LineaCoreTests`, запуск — `Scripts/test-core.sh`.

## 1. Принципы

1. **Детерминированное ядро, LLM только формулирует.** State Engine и Decision
   Engine — чистые функции над данными; их результат воспроизводим в тесте.
   LLM получает типизированные факты и переписывает их по-человечески; она
   никогда не меняет порядок задач и не придумывает чисел.
2. **Ядро — Foundation-only.** `Linea/Core` не импортирует SwiftUI, SwiftData,
   HealthKit. Поэтому оно собирается и тестируется в Docker на Linux без Xcode,
   а всё, что зависит от Apple-фреймворков, живёт в адаптерах (`Linea/Data`,
   `Linea/Platform`) и проверяется на Mac.
3. **Коннекторы, а не переделки.** Новый источник данных — это новый
   `ContextProvider` (+ при необходимости `StateAnalyzer`, `PlanRule`,
   `NudgeRule`) и одна строка регистрации в composition root. Движки подписаны
   на **виды сигналов** (`SignalKind`), а не на провайдеров.
4. **Время только через `TimeContext`.** Движки не вызывают `Date()` и
   `Calendar.current` (линтер `Scripts/check-layers.sh`). Контейнер тестов
   живёт в UTC, телефон пользователя — нет; без явного календаря сценарий
   «14:30» невоспроизводим.
5. **План — отдельная сущность.** «Принять план» и пересчёт никогда не меняют
   задачи пользователя. Куда планировщик поставил задачу — в `DayPlan`, не в
   `LineaTask`. Так история «план vs факт» остаётся чистой для Feedback Engine.
6. **Никогда не фабриковать «обычное».** Фраза «меньше обычного» допустима
   только при надёжном личном baseline (≥ 7 дней). До этого — абсолютные
   значения и «собираю базу: день N из 7».
7. **Мало регуляторов обучения.** Три кнопки в день не калибруют пять весов.
   Feedback Engine меняет только ограниченный набор параметров
   (`Calibration`), веса scoring логируются (`ScoreBreakdown`), но не учатся.
8. **Приватность.** Сырые данные HealthKit не покидают устройство. Наружу
   (если появится облачная LLM) уходят только производные факты и только с
   явного согласия.

## 2. Слои и папки

```text
Package.swift                 SwiftPM-манифест ТОЛЬКО для Linux/CI (path: "Linea/Core")
Tests/LineaCoreTests/         Swift Testing; строго вне Linea/ (synchronized group Xcode)
Scripts/test-core.sh          docker run … swift test
Scripts/check-layers.sh       линтер границ ядра
HealthKitManager.swift        остаётся в корне (явно прописан в pbxproj), расширяется extension-файлами
Linea/
├── App/                      LineaApp (composition root), AppState, RootView
├── Core/                     ★ Foundation-only. Собирается SwiftPM и Xcode одинаково
│   ├── Domain/
│   │   ├── Models/           LineaTask, LineaGoal, Signal, Provider, Commitment, ContextSnapshot,
│   │   │                     HealthHistory (DailyHealthSummary, Baseline, SleepNight), UserProfile,
│   │   │                     NutritionProfile/MealLog, UserState, Fact, DayPlan/PlanBlock/Recommendation,
│   │   │                     Nudge, UserFeedback, Calibration/EngineConfig, DayRecord, TimeContext
│   │   ├── Protocols/        ContextProvider, StateAnalyzer/PlanRule/NudgeRule, Explainer, репозитории
│   │   └── UseCases/         BuildDayPlan, AcceptPlan, CheckIn (нуджи), RespondToNudge, RecordDayRating
│   ├── Intelligence/
│   │   ├── ContextEngine/    сбор снапшота из провайдеров, CommitmentMapper
│   │   ├── StateEngine/      SleepAnalyzer, BaselineCalculator, анализаторы, EnergyFusion, Circadian
│   │   ├── DecisionEngine/   TaskScorer, FreeWindows, DayPlanner, правила (DayBrief, LoadAdjustment,
│   │   │                     BehindSchedule, EveningCheckIn), NudgeEngine
│   │   ├── FeedbackEngine/   калибровка по истории DayRecord
│   │   └── LLM/              RuleBasedExplainer, RussianText, ExplanationValidator, FallbackExplainer
│   └── Connectors/           Foundation-only части коннекторов (Nutrition: провайдер окон еды + правило)
├── Data/                     Apple-фреймворки разрешены; реализует протоколы Core
│   ├── Persistence/          SwiftData-сущности (TaskEntity, GoalEntity, DayRecordEntity, …)
│   ├── Repositories/         Local*Repository
│   ├── HealthKit/            HealthKitContextProvider, HealthKitManager+History, HK-расширения
│   └── Providers/            Apple-зависимые провайдеры (Calendar/EventKit — следующий коннектор)
├── Platform/                 адаптеры iOS: NudgeScheduler (UserNotifications), FoundationModelsExplainer
├── Features/                 SwiftUI-экраны и view-facing store'ы (Today, Plan, Health, Nutrition, Profile, AI)
├── Components/, DesignSystem/  без изменений
└── Services/                 SampleData/SampleModels — только для ещё не подключённых экранов
```

Правила зависимостей:

| Слой | Может импортировать | Не может |
|---|---|---|
| `Core/Domain` | Foundation | всё остальное |
| `Core/Intelligence`, `Core/Connectors` | Foundation, Domain | Apple-фреймворки, `Date()` |
| `Data`, `Platform` | Core + SwiftData/HealthKit/EventKit/UserNotifications/FoundationModels | Features |
| `Features` | Core, store'ы | HealthKit, SwiftData, UNUserNotificationCenter напрямую |
| `App` | всё | — (единственное место регистрации провайдеров и правил) |

Изоляция: проект собирается с `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
поэтому **все типы и протоколы ядра помечены `nonisolated`** и являются
`Sendable`. Store'ы и `Local*Repository` остаются `@MainActor`, как сейчас.
`Package.swift` повторяет настройки Xcode (default isolation, language mode
5, пять фич Approachable Concurrency), чтобы семантика в двух «домах» кода
совпадала.

## 3. Модель данных

Все типы — `Codable`, `Sendable`, value-типы. Ниже — назначение и ключевые
поля; полные определения в `Linea/Core/Domain/Models`.

| Тип | Что это | Ключевые поля |
|---|---|---|
| `ContextSignal` | единица контекста от любого коннектора | `kind: SignalKind`, `value`, `start/end`, `source: ProviderID`, `quality`, `attributes` |
| `SignalKind` | строковый расширяемый вид сигнала | `health.sleep.segment`, `health.hrv.sdnn`, `health.heartRate.resting`, `health.steps`, `health.activeEnergy`, `health.workout`, `time.commitment` + свои у коннекторов |
| `Commitment` | занятое время (встреча, окно еды, тренировка, задача с временем) | `title`, `start/end`, `kind`, `source`, `taskID?` |
| `ContextSnapshot` | всё, что видели движки, заморожено | `signals`, `providerStatuses`, `tasks`, `goals`, `commitments`, `profile`, `nutrition`, `meals` |
| `DailyHealthSummary` | дневные агрегаты `[SignalKind: Double]` | `day`, `values` |
| `Baseline` | личная норма по одному kind | `median`, `spread` (1.4826·MAD с полом), `sampleCount`, `isReliable (≥7)`, `confidence` |
| `SleepNight` | ночь после дедупликации источников | `bedtime`, `wakeTime`, `asleepSeconds`, `inBedSeconds`, `stages`, `quality`, `awakenings` |
| `UserState` | состояние на день | `components: [StateComponent]`, `energy 0…1`, `confidence`, `loadAdvice`, `sleepNight`, `baselineProgress`, `facts` |
| `Fact` | типизированный факт для текста | `sleepDuration`, `sleepVsUsual`, `recovery(level)`, `coldStart`, `hardWorkDeadline`, `nextCommitment`, … |
| `DayPlan` | ответ «что делать сегодня» | `blocks: [PlanBlock]`, `topTaskIDs`, `deferredTaskIDs`, `recommendations`, `status`, `version` |
| `PlanBlock` | тайм-блок | `kind (focus/commitment/meal/rest)`, `taskID?`, `start/end`, `score: ScoreBreakdown?`, `isTop`, `isPinned` |
| `Recommendation` | структурированный совет | `kind`, `message` (rule-based), `explanation?` (LLM), `facts`, `actions` |
| `Nudge` | момент-зависимый вопрос | `kind`, `fireAt`, `taskID?`, `title/body`, `actions`, `cancelWhen` |
| `UserFeedback` | ответ пользователя | `kind: dayRating / planAccepted / nudgeResponse / taskPostponed / …`, `energy`, `loadAdvice` |
| `Calibration` | что выучил Feedback Engine | `energyBias`, `reduceThreshold`, `pushThreshold`, `capacityFactor`, `estimateMultiplier`, `nudgeGraceMinutes`, `nudgeCooldownMultiplier`, `changeLog` |
| `EngineConfig` | константы продукта (не учатся) | веса scoring, веса компонент, окна, лимиты |
| `UserProfile` | рабочий день, тихие часы, вечерний опрос, целевой сон | |
| `NutritionProfile`, `MealLog` | диета/ограничения/продукты/заболевания-теги, окна еды; отметка «поел» | |
| `DayRecord` | документ дня (JSON-блоб в SwiftData) | `snapshot`, `state`, `plan`, `nudges`, `feedback` |

### Задачи и цели (расширение существующих типов, аддитивно)

`LineaTask` += `deadline: Date?`, `scheduledStart: Date?` (фиксированное время =
обязательство), `estimatedMinutes: Int?`, `cognitiveDemand: CognitiveDemand`
(`light 0.3 / normal 0.6 / deep 0.9`), `goalID: UUID?`, `completedAt: Date?`.
`TaskPriority` += `.low`; `score`: low 0.2 / normal 0.5 / important 1.0.
Три времени задачи различаются намеренно: `date` — день, на который задача
запланирована; `deadline` — к какому моменту должна быть сделана (urgency);
`scheduledStart` — пользователь сам зафиксировал время.

С 08.10.2026 задача помнит, какие параметры задал человек
(`userFields: Set<TaskField>?`, §21): их Linea сама не перезаписывает.

`LineaGoal` += `horizon: GoalHorizon (.week/.month)`, `startDate`,
`isActive`. Дата окончания вычисляется. Лимит «1–3 активные» — мягкий
(предупреждение в UI).

Персистентность: новые поля `TaskEntity`/`GoalEntity` — optional/с дефолтом
(lightweight-миграция SwiftData). Новые сущности (`DayRecordEntity`,
`CalibrationEntity`, `UserProfileEntity`, `NutritionProfileEntity`,
`MealLogEntity`) хранят JSON-блобы со `schemaVersion`.

## 4. Протоколы

```swift
nonisolated protocol ContextProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    var provides: Set<SignalKind> { get }
    func fetchContext(_ request: ContextRequest) async throws -> ProviderFetchResult
}
// ContextRequest { day: DateInterval, time: TimeContext, historyDays: Int }
// ProviderFetchResult { signals, status: ProviderStatus (.ready/.noData/.indeterminate/.unauthorized/…) }

nonisolated protocol StateAnalyzer: Sendable { var kind: StateComponentKind { get }; func analyze(_ input: StateInput) -> StateComponent? }
nonisolated protocol PlanRule: Sendable   { var id: String { get }; func apply(to plan: inout DayPlan, context: PlanningContext) -> [Recommendation] }
nonisolated protocol NudgeRule: Sendable  { var id: String { get }; func nudges(_ context: NudgeContext) -> [Nudge] }
nonisolated protocol Explainer: Sendable  { var id: String { get }; func explain(_ request: ExplanationRequest) async throws -> Explanation }
```

`ContextEngine.capture` принимает `additionalProviders`: коннекторы, чьи
данные вызывающая сторона только что загрузила (профиль питания меняется между
обновлениями, поэтому его провайдер создаётся на каждый сбор контекста, а не
регистрируется один раз).

Отличия от брифового `fetchContext() async throws -> [ContextSignal]`:
явный запрос (день, время, глубина истории) — иначе провайдер вызовет
`Date()` и тест станет недетерминированным; статус провайдера в результате —
чтобы честно показывать «нет данных о сне» (HealthKit не раскрывает статус
read-доступа, отсюда `.indeterminate`). Ошибка провайдера превращается в
`ProviderStatus.failed`, снапшот собирается без него.

Задачи и цели **не** сигналы: они — предмет решения и лежат в снапшоте
типизированно. Единственное исключение: задача с `scheduledStart` становится
`Commitment` (через `CommitmentMapper` в ContextEngine).

## 5. Поток данных wow-сценария

**Утро (открытие приложения).**
1. `IntelligenceStore.refresh()` загружает задачи, цели, профиль, питание,
   калибровку, историю дневных сводок (28 дней из HealthKit, кэш в памяти).
2. `ContextEngine.capture` опрашивает провайдеры параллельно (таймаут 5 с):
   HealthKit (сегодня + история сна за ночь), Nutrition (окна еды →
   `.commitment`), позже Calendar. Собирает `ContextSnapshot`, обязательства
   = `.commitment`-сигналы + задачи с `scheduledStart`.
3. `BaselineCalculator` → `BaselineSet` (медиана/MAD за 28 дней без сегодня).
4. `StateEngine.evaluate` → `UserState` (сон 6:03 ниже обычного, recovery
   ниже обычного → energy ≈ 0.38, `loadAdvice = .reduce`).
5. `DecisionEngine.plan` → `DayPlan`: A «Презентация КП» 09:00–10:30,
   C «Ответить на письма» 10:40–11:10, обед 13:00–13:40, B «Разработка Linea»
   13:40–15:40, созвон 15:50, тренировка 17:00; `topTaskIDs = [A, B, C]`;
   факт `hardWorkDeadline(12:00)`.
6. `Explainer` → «Доброе утро. Сегодня нагрузку лучше немного снизить. У тебя
   есть 3 приоритетных действия. Самую сложную работу предлагаю сделать до
   12:00.» Кнопка «Принять план».
7. `AcceptPlanUseCase`: план → `.accepted`, `NudgeEngine` считает нуджи дня с
   готовым текстом; `NudgeScheduler` (Platform) ставит локальные уведомления с
   действиями; при `toggleTask(done)` уведомление отменяется.

**14:30 (нудж).** Открытие приложения или уведомление → `CheckInUseCase`:
блок A закончился 10:30, задача не закрыта, следующее обязательство — созвон
15:50 → «План немного отстаёт. До следующего обязательства осталось 1 ч 20 мин.
Закрываем «Презентация КП» сейчас или переносим?» → `RespondToNudgeUseCase`:
«сейчас» — фидбек + пересчёт плана от 14:30; «переносим» — `task.date =
завтра` через `PlanStore`, фидбек `taskPostponed`, пересчёт.

**Вечер.** С 20:30 (или после последнего обязательства) — «Как прошёл день?»
→ `RecordDayRatingUseCase`: `UserFeedback(.dayRating)` в `DayRecord`,
`FeedbackEngine.calibrate(history)` → `Calibration`.

Фоновых задач в v1 нет: «реакция в 14:30» = заранее запланированное локальное
уведомление + пересчёт при каждом открытии. `BGTaskScheduler` — v1.1.

## 6. State Engine

Обозначения: `clamp(x,a,b)`, `lin(x,x0,x1) = clamp((x−x0)/(x1−x0),0,1)`.

**SleepAnalyzer** (из `.sleepSegment`):
- окно ночи для дня D: `[D−1 18:00, D 12:00]`; сегмент относится к ночи, в
  которую попадает его середина; сегменты вне окон — дневной сон (в v1 не
  используется);
- группировка по `attributes.sourceBundle`; выбирается источник со стадиями
  (core/deep/rem), при равенстве — с наибольшей суммой asleep. Это чинит
  двойной счёт Watch + iPhone в текущем `sleepDuration()`;
- `asleep` = длина объединения интервалов стадий `{core, deep, rem,
  unspecified}`; `inBed` = объединение `inBed` (или span); только `inBed` →
  `asleep = 0.9·inBed`, `quality 0.5`; стадии → `quality 1.0`; без стадий 0.8;
- `bedtime` = начало первого asleep-сегмента, `wakeTime` = конец последнего,
  `awakenings` = разрывы > 5 мин.

**Валидация входов:** сон > 16 ч, HRV ∉ (0, 300], RHR ∉ [30, 120] — отбрасываются.

**Дневные ряды** (`DailyHealthSummary`): `sleepAsleep`, `sleepInBed`,
`sleepBedtime`, `hrvLog = ln(медиана ночных HRV 00:00–12:00, иначе всех за
день)`, `restingHeartRate`, `steps`, `activeEnergy`, `workoutMinutes`.

**Baseline** (окно 28 дней, без сегодня): n < 3 → нет; `median`, `spread =
max(1.4826·MAD, floor)`; полы: сон 30 мин, `hrvLog` 0.10, RHR 2 bpm, шаги
1500, энергия 100 ккал, тренировки 15 мин, отбой 30 мин; `isReliable = n ≥ 7`;
`confidence = clamp((n−3)/8)`; `z = clamp((x−median)/spread, −3, 3)`.

**Компонент `sleep`:** `ref = isReliable ? median : profile.sleepNeedSeconds`
(во втором случае confidence ≤ 0.4). `durationScore = lin(asleep, 0.6·ref,
ref)`; `efficiencyScore = lin(asleep/inBed, 0.75, 0.92)` если inBed известен;
`debt = Σ_{7 дней} max(0, ref − asleep_i)` (cap 10 ч), `debtScore = 1 −
lin(debt, 0, 6 ч)` при ≥ 4 днях данных; веса 0.60 / 0.15 / 0.25 по доступным;
итог `× (0.8 + 0.2·quality)`. Уровень: `z ≤ −0.7` или `asleep ≤ 0.85·ref` →
`belowUsual`; `z ≥ 0.7` → `aboveUsual`; без надёжного baseline → `unknown`.
Факты: `sleepDuration`, `sleepBaseline`, `sleepVsUsual` (только при
надёжном baseline), `sleepShortAbsolute` при < 5 ч.

**Компонент `recovery`:** `hrvScore = clamp(0.5 + 0.2·z_hrvLog)`, `rhrScore =
clamp(0.5 − 0.2·z_rhr)`; `recovery = (0.6·hrvScore·c_hrv + 0.4·rhrScore·c_rhr)
/ (0.6·c_hrv + 0.4·c_rhr)`, `c` = confidence соответствующего baseline (0,
если сегодня значения нет). Уровень по взвешенному z (±0.7). Cold start
(значение есть, baseline нет): `score 0.5, confidence 0.15`, факт
`coldStart(days, needed: 7)`. Абсолютные популяционные нормы HRV не
используются: межличностный разброс больше внутриличностного.

**Компонент `strain`** (упрощённо, без TRIMP): `yesterdayStrain =
workoutMinutes_вчера / max(median + spread, 60)`; `score = clamp(1 −
0.5·max(0, yesterdayStrain − 1))`; нет тренировок в окне → компонент
отсутствует. Факт `highLoadYesterday` при `yesterdayStrain ≥ 1.3`.

**EnergyFusion:** веса `sleep 0.45, recovery 0.35, strain 0.20, fuel 0.10`
нормируются по доступным компонентам; `C = Σ w·c / Σ w`; `raw = Σ w·c·s / Σ
w·c`; `energy = clamp(C·raw + (1−C)·0.5 + energyBias)`; `confidence = C`.
`loadAdvice`: `C < 0.35 → unknown`; `energy < reduceThreshold (0.40) → reduce`;
`energy > pushThreshold (0.70)` и `recovery ≥ 0.6 → push`; иначе `normal`.
Гистерезис 0.03 относительно вчерашнего `loadAdvice`. Абсолютное правило:
сон < 5 ч → минимум `reduce`.

**Circadian** (хронотип-нейтральная кривая бодрости по локальному часу,
линейная интерполяция): 6→0.45, 7→0.55, 8→0.70, 9→0.85, 10→0.95, 11→1.00,
12→0.90, 13→0.75, 14→0.65, 15→0.70, 16→0.80, 17→0.85, 18→0.80, 19→0.70,
20→0.60, 21→0.50, 22→0.40, 23→0.30. `capacity(t) = (0.5 + 0.5·energy)·alertness(t)`
— плохой сон не обнуляет утро.

**Опорные числа wow-сценария** (закреплены тестами в
`Tests/LineaCoreTests/StateEngine/StateEngineTests.swift`, фикстура
`WowFixture`: сон 6:03 при норме 7:13, HRV 38 при 52, RHR 58 при 54):

| Величина | Значение |
|---|---|
| z сна | −2.33 |
| компонент `sleep` | 0.674, уверенность 1.0, уровень belowUsual |
| компонент `recovery` | 0.04, уверенность 1.0, уровень belowUsual |
| компонент `strain` | отсутствует (вчера не было тренировки) |
| energy | 0.396 |
| loadAdvice | `.reduce` |

Замечание: в фикстуре история слишком ровная, поэтому разбросы упираются в
полы (сон 30 мин, ln-HRV 0.10), а z HRV клампится на −3 — отсюда очень низкий
`recovery`. На реальных данных разброс больше и оценка мягче; полы существуют
именно для того, чтобы у очень стабильного человека маленькое отклонение не
превращалось в «катастрофу».

**Cold start / деградация:** HealthKit не подключён → компонентов нет,
`energy 0.5`, `loadAdvice unknown`, factor `energyFit` исключается из scoring
с перераспределением веса, текст «Не вижу данных Apple Health». Дни 1–6 →
абсолютные значения, «собираю базу: день N из 7», без слова «обычно».

## 7. Decision Engine

Кандидаты: открытые задачи с `date == today`, просроченные, с `deadline ≤
today + 2 дня`, а также без даты, но привязанные к активной цели (не более 3
по score). Задачи с `scheduledStart` — обязательства, в жадный проход не
входят, но получают score и могут быть в Top-3.

**Score** — пять факторов брифа (все 0…1). С 02.10.2026 они не складываются
в один балл, а служат кирпичами двух оценок движка приоритизации — важности и
уместности сейчас (§16, ADR-025); расстановка выбирает `importance × action`.
Исходная формула v1 (веса больше не используются):

| Компонент | Вес | Формула |
|---|---|---|
| urgency | 0.30 | `deadlineMoment = deadline ?? (date → конец рабочего дня)`; без дедлайна 0.15; `slack = часы до дедлайна − est/60`; `slack < 0 → 1`; иначе `exp(−slack/36)` |
| importance | 0.25 | `priority.score` + 0.2, если задача привязана к активной цели с горизонтом неделя (cap 1) |
| goalAlignment | 0.15 | без `goalID` → 0; цель неактивна/завершена → 0.2; иначе `0.6 + (неделя 0.3 / месяц 0.15) + 0.1·exp(−daysLeft/7)`, `× (1 − 0.3·progress)` |
| energyFit | 0.20 | `capacity(slotStart)`; `gap = demand − capacity`; `gap ≤ 0 → 1 − 0.5·|gap|`; иначе `clamp(1 − 1.5·gap)`. При `state.confidence < 0.35` компонент исключается |
| durationFit | 0.10 | `est ≤ окно → 1`; иначе `0.6·окно/est`; окно < 15 мин → 0 |

`total = Σ w·f / Σ w` по доступным компонентам. `ScoreBreakdown` сохраняется
в каждом блоке.

**Свободные окна:** `[max(now, workdayStart), workdayEnd]` минус
обязательства; после каждого поставленного блока буфер 10 мин; окна короче 15
мин отбрасываются. `availableMinutes = Σ окон × capacityFactor_day`, где
`capacityFactor_day = calibration.capacityFactor × (reduce 0.75 / normal 1.0 /
push 1.1 / unknown 0.9)`.

**Расстановка** (жадная, хронологическая, детерминированная): в каждом окне
`t = start`; выбирается `argmax score(task, t, остаток окна)` среди кандидатов,
удовлетворяющих ограничениям; блок `[t, t + est·estimateMultiplier]`; если
задача не влезает целиком и остаток < 80 % est — пропускается до следующего
окна; `t += длительность + буфер`. Суммарные focus-минуты ≤
`availableMinutes`; остальные кандидаты → `deferredTaskIDs` с фактом
`taskDeferred`. Tie-break: `createdAt`, затем `id`.

**Ограничения при `reduce`:** deep-блоки (demand ≥ 0.7) разделяются ≥ 60 мин
не-deep времени; deep-блок не начинается после 16:00. При `normal` — только
буферы. Так «сложное до 12:00» и «разработка после обеда» возникают из
кривой бодрости и ограничений, а не из хардкода.

**Top-3:** три самые важные (`importance`, §16) задачи среди поставленных
(включая фиксированные) → `topTaskIDs`, `isTop`. Факт `topTaskCount(N)`.
`hardWorkDeadline(12:00)` — если задача с максимальным demand поставлена
целиком до 12:00.

**PlanRule** (после расстановки, по умолчанию `[DayBriefRule()]`):
- `DayBriefRule` — утренний бриф `Recommendation(.dayBrief)`: собирает факты
  плана (`topTaskCount`, `hardWorkDeadline`) и состояния (сон, восстановление,
  cold start, отсутствующие данные) и отдаёт их рендереру. Именно его текст
  читает пользователь на Today.
- `LoadAdjustmentRule` — отдельная карточка «снизить нагрузку», если нужен
  совет без брифа.
- `NutritionRule` — см. §10.
Правила детерминированы и могут добавлять блоки `.meal/.rest`.

Правило, которому нужен текст, объявляет себя `RendererAwarePlanRule`
(`bound(to:)`), и движок передаёт ему свой `TextRenderer`. Так протоколы
Domain остаются без знания о текстах, а список правил — обычным литералом.

**Nudge Engine** (по принятому плану):
- `BehindScheduleRule`: для top-блока с незакрытой задачей `fireAt = block.end
  + grace (15)`; если сейчас уже позже — нудж «due now». Текст: «План
  немного отстаёт. До следующего обязательства осталось {H ч M мин}.
  Закрываем «{title}» сейчас или переносим?»; без обязательств — «До конца
  рабочего дня осталось …». Действия: `[finishNow, defer]`, если до
  обязательства ≥ 0.8·est, иначе `[defer]`. `cancelWhen: [.taskDone]`.
  Cooldown 90 мин × `nudgeCooldownMultiplier`, тихие часы, ≤ 3 в день,
  окно до обязательства ≥ 20 мин.
- `EveningCheckInRule`: `fireAt = max(profile.eveningCheckIn, конец последнего
  обязательства)`; «Как прошёл день?» `[rateDay]`; `cancelWhen: [.dayRated]`.

**Replan** (`DayPlanner.replan(from: now)`): прошедшие блоки и `isPinned`
сохраняются, окна после `now` пересчитываются, `version += 1`, старый план
→ `.superseded`.

## 8. Feedback Engine

`FeedbackEngine.calibrate(history: [DayRecord], previous: Calibration, time)
-> Calibration` — пересчёт из истории (идемпотентно по построению):
- `energyBias`: EMA (α 0.3) по дням с оценкой и `state.confidence ≥ 0.5`:
  `predicted = energy ≥ 0.65 → +1, ≤ 0.40 → −1, иначе 0`; `r = rating −
  predicted`; шаг `0.05·r`; clamp ±0.15;
- пороги: «Тяжело» при `push` → `pushThreshold += 0.03` (≤ 0.85); «Тяжело»
  при `normal` → `reduceThreshold += 0.02` (≤ 0.55); «Отлично» при `reduce` →
  `reduceThreshold −= 0.03` (≥ 0.30). Сдвиг применяется, если паттерн
  повторился ≥ 2 раз из последних 3 таких дней;
- `capacityFactor = 0.8·prev + 0.2·ratio` по дням с планом и ≥ 30
  запланированных минут, итог — clamp 0.5…1.1. `ratio` — доля минут рабочих
  блоков плана, пришедшаяся на закрытые задачи, из итога дня
  (`DayReportSummary.completionRatio`, clamp 0.4…1.1); без итога — по оценке
  дня: «Отлично» 1.0, «Нормально» 0.85, «Тяжело» 0.6 (ADR-019);
- `nudgeCooldownMultiplier`: два `dismiss` подряд → 2.0, `finishNow` → 1.0;
  `nudgeGraceMinutes`: доля переносов > 50 % за 7 дней → 30, иначе 15.
- Каждое изменение → `changeLog` (показывается в Profile, есть «Сбросить»).

Веса scoring **не** обучаются.

## 9. LLM / объяснения

- `RuleBasedExplainer` (Core, всегда доступен) — источник истины: тексты
  wow-сценария закреплены golden-тестами. Тексты собираются только из
  `Fact`; `RussianText` — форматирование «1 ч 20 мин», «6:03», склонения.
- `FallbackExplainer(primary: Explainer?, fallback: RuleBasedExplainer,
  timeout 3 с, validator)`: `headline` всегда rule-based; LLM пишет только
  `body`/`explanation`. `ExplanationValidator`: числа в тексте ⊆ чисел из
  фактов, кириллица ≥ 70 %, ≤ 3 предложений, запрещённые слова (диагноз,
  болезнь, лекарств…).
- `FoundationModelsExplainer` (Platform, `#if canImport(FoundationModels)`):
  on-device модель iOS 26 (`SystemLanguageModel.default.availability`,
  `supportsLocale(ru)`), `@Generable` структура ответа. Недоступна —
  работаем на шаблонах, это норма.
- `RemoteExplainer` (позже): `POST /v1/explain` через бэкенд-прокси, ключ на
  сервере, только с согласия; в запросе — факты, не сэмплы.

## 10. Рецепт коннектора

Общий рецепт (ядро не меняется):
1. Foundation-only часть — `Linea/Core/Connectors/<Name>/`: `extension
   SignalKind` со своими видами, провайдер/правило/анализатор, тесты в
   Docker.
2. Apple-зависимая часть — `Linea/Data/Providers/<Name>/` (EventKit,
   HealthKit, SwiftData-сущности).
3. Регистрация: одна-три строки в composition root (`LineaApp`/`AppContainer`).
4. Info.plist-ключи и entitlements — на Mac.

**Calendar (следующий коннектор, v1.1):** `CalendarContextProvider`
(EventKit) → события дня как `ContextSignal(kind: .commitment, attributes:
[label, commitmentKind: meeting, eventID])`. `.commitment` — уже core-kind:
планировщик вычитает события из окон, нудж считает «до следующего
обязательства», текст перечисляет. Плюс `INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription`.
Тест ядра со стаб-провайдером уже покрывает поведение.

**Nutrition (в v1):** `NutritionContextProvider` (Core/Connectors/Nutrition,
Foundation-only) из `NutritionProfile` и `[MealLog]` эмитит `.commitment`
для окон еды (kind `meal`) и `nutrition.mealLogged`. `NutritionRule: PlanRule`
— при `loadAdvice == .reduce` рекомендация «обед пораньше и легче» с
продуктами из `preferredProducts` минус `excludedProducts`; при
запланированной тренировке — «перекус за 1,5 ч». Так возникает связь
сон → ёмкость → план и еда — критерий успеха первой версии.

Следующие по тому же рецепту: Location (`.commitment` на дорогу), Screen Time
(`StateAnalyzer` вечернего экрана), Gmail/Work (`PlanRule` с защитой блока
под дедлайны из писем), другие носимые (те же health-kinds).

## 11. Тесты

`Tests/LineaCoreTests`, Swift Testing, запуск `Scripts/test-core.sh`:
Состояние на 2026-09-10: **153 теста ядра зелёные** в Docker.

- `Fixtures/WowFixture` — сценарий брифа с явными числами: Europe/Moscow,
  2026-09-09, сон 6:03 (21 780 с) при обычных 7:13, HRV 38 при обычных 52,
  RHR 58 при 54, задачи A/B/C, цель «Запустить MVP Linea», обед 13:00,
  созвон 15:50, тренировка 17:00 — так «1 ч 20 мин» получается из данных;
- `SleepAnalyzerTests` (два источника, только inBed, через полночь),
  `BaselineTests`, `StateEngineTests` (reduce, cold start 0/2/3/7 дней,
  отсутствие HRV), `TaskScorerTests`, `DayPlannerTests` (порядок A-C-B,
  блоки не пересекают обязательства, детерминизм), `NudgeEngineTests`
  (14:30 → напоминание с двумя ответами; задача закрыта → пусто; тихие часы →
  пусто; вечерний вопрос и его исчезновение после оценки), `FeedbackEngineTests`,
  `RuleBasedExplainerTests` (golden-строки брифа слово в слово),
  `ExplanationValidatorTests` (числа вне фактов, латиница, «обычно» без базы,
  чужое название задачи), `FallbackExplainerTests` (ошибка, таймаут,
  галлюцинация → шаблон), `WowScenarioTests` (end-to-end утро → 14:30 → вечер,
  включая деградацию без данных здоровья), `ContextEngineTests`,
  `NutritionConnectorTests`, `CodableTests` (round-trip DayRecord).

## 12. Срез v1 и что осознанно не делаем

В v1: расширенные задачи/цели с редакторами; история HealthKit 28 дней и
аналитика сна; State/Decision/Nudge/Feedback Engine; Today с утренним
брифом, «Принять план», тайм-блоками, карточкой нуджа и вечерней оценкой;
локальные уведомления с действиями; профиль питания + окна еды + правило;
шаблонные объяснения; on-device LLM за флагом.

Не в v1: фоновые задачи (`BGTaskScheduler`), календарь (EventKit — v1.1),
облачная LLM и бэкенд, аккаунты и синхронизация, обучение весов, TRIMP/ACWR,
хранилище сырых сигналов, `VersionedSchema` (пока изменения аддитивны),
AI-мэтчинг задача↔цель (в v1 — явная связь + подсказка по совпадению слов).

## 13. Итог дня и ядро контекста

Подробно для людей — `Docs/check-in.md`; решения — ADR-016…021. Итог дня
целиком на телефоне (ADR-021): распознаёт GigaAM или диктовка iPhone,
разбирают правила.

**Поток.** `SpeechTranscribing` (GigaAM или диктовка iPhone) → `CheckInRequest` (рассказ,
`relevantTasks`: задачи дня, закрытые в этот день, просроченные, до 10 без
дня, всего ≤ 30; известные факты) → `CheckInExtracting` →
`CheckInExtractionValidator` → `CheckInDraft` (правит человек) →
`SubmitCheckInUseCase`.

**Разбор правилами** (`RuleBasedCheckInExtractor`, `CheckInText`):
- рассказ делится на предложения и части по запятым и союзам: «и», «потом»,
  «ещё» продолжают мысль и передают статус («сделал отчёт и презентацию»);
  «а», «но», «зато» — противопоставление, статус не передаётся;
- статус части: частично («начал», «наполовину», «не до конца») → не сделано
  («не», «нет», «перенёс», «отложил», «пропустил») → сделано («сделал»,
  «закрыл», «провели», «успел»…); ключевые слова названия задачи из поиска
  маркеров исключаются, глаголы названия («ответить») — нет;
- совпадение названия: основы слов (≤ 5 букв, без окончания), глаголы вроде
  «сделать», «подготовить» весят 0.3; нужно ≥ половины веса, но не больше двух
  слов; «полное» совпадение — все ключевые слова или хотя бы два. Неполное
  совпадение не перебивает полное и не мешает считать часть «сделанным сверх
  плана»;
- «всё сделал» / «ничего не успел» — про задачи дня без своего статуса;
- длительности: «3 часа», «часа три», «полтора часа», «два с половиной часа»,
  «час двадцать», «минут на сорок», «полчаса»; «в два часа» — время на часах.
  Объём дня — «всего N» или сумма длительностей в предложениях про работу;
- оценка дня и силы — словари с «не» (переворот, ×−0.5) и смягчением
  («немного», ×0.5): ≤ −1 «Тяжело», ≥ 1 «Отлично».

**Разбор моделью** (`CheckInPrompt`, `RemoteCheckInExtractor`): строгий JSON
(`response_format: json_object`), задачи под номерами. При противоречии
верится осторожному: not_done > partial > done > mentioned. Валидатор: номера
только из списка; сверх плана ≤ 8, без дублей задач; объём 5…960 мин; фраза
≤ 160 символов, кириллица ≥ 60 %, числа ⊆ чисел рассказа, без медицины; в
память ≤ 3 факта от модели (≤ 5 явных «запомни»), 8…140 символов, про
здоровье — только по явной просьбе. `FallbackCheckInExtractor`: модель
главная, от правил берутся явные «запомни» и пропущенные моделью задачи
(без галочки).

**Сохранение** (`SubmitCheckInUseCase`): отмеченное закрывается моментом
итога, но не позже конца того дня; незакрытое из задач дня — на завтра
без фиксированного времени, кроме встреч, которые ещё впереди; запись
дневника с выжимкой (`DayDigestBuilder`); память — `MemoryConsolidator`;
в `DayRecord.feedback` — `dayReport` и `dayRating` (повторный итог заменяет);
вечерний нудж снимается; калибровка пересчитывается.

**Память** (`MemoryConsolidator`): ≤ 40 фактов; похожесть — Жаккар по основам
≥ 0.5 → +1 подтверждение; явное «запомни» и записанное вручную закрепляется;
незакреплённый факт с одним подтверждением старше 60 дней забывается; сверх
лимита уходит незакреплённый с наименьшей силой `подтверждения + e^(−дни/30)`.

**Контекст** (`UserContextBuilder`, бюджет по умолчанию 900 токенов, оценка
`TokenEstimator`: кириллица 2.5 символа на токен, остальное 4): факты
(закреплённые → относящиеся к вопросу → сильные, ≤ 20, ≤ 45 % бюджета) →
последние 7 дней (два свежих полной выжимкой, остальные строкой цифр,
≤ 30 %) → старые дни по вопросу (`JournalSearch`: сумма `ln(1 + N/df)` по
совпавшим основам × `(0.5 + 0.5·0.5^(дни/30))`, до 3 дней, с цитатой из
рассказа, если в выжимке совпадения нет). Сырой рассказ в контекст не
попадает; рассказы старше 60 дней стираются (`CheckInEntry.compacted`).


## 14. Быстрый ввод задачи

Решение — ADR-023. Код — `Linea/Core/Intelligence/TaskCapture`, тесты —
`Tests/LineaCoreTests/TaskCapture`.

**Поток.** Строка (набранная, надиктованная кнопкой микрофона через GigaAM или
диктовкой клавиатуры) → `QuickTaskParser.parse` → `QuickTaskParse` →
`QuickTaskDraft.resolve` (чипы + сказанное + значения по умолчанию) →
`QuickTaskResolution` → `task(id:createdAt:)` → `PlanStore.saveTask`.

**Разбор** (`CaptureTokenizer`, `QuickTaskParser`). Строка делится на слова,
числа, время «15:00» и даты «15.10», у каждого куска — место в строке.
Распознанное вырезается из названия; между оставшимися словами — исходные
знаки. Порядок правил: служебное в начале («добавь задачу», «надо», «напомни
мне») → приоритет → срок → день → время начала → длительность → цель.
- День: «сегодня», «завтра», «послезавтра», дни недели («в пятницу», «в эту
  среду» — сегодня, «в следующую пятницу» — на следующей неделе), «на неделе»,
  «на следующей неделе» (понедельник), «на выходных», «через 3 дня», «15
  октября», «15.10», «25 числа». Прошедшая дата без года — следующего года.
- Срок: «до/к» + день или время («до 18:00», «к пятнице», «до пятницы 15:00»,
  «до вечера» — 18:00, «до обеда» — 12:00, «к завтрашнему обеду», «до
  сегодняшнего вечера», «до конца дня»), «дедлайн/срок …».
  День без времени — конец рабочего дня; время без дня — сегодня, а если
  прошло — завтра. «До конца недели» — то же, что «на неделе».
- Время начала: «в 15:00», «в 7 вечера», «в 9 утра», «в 10», голое «15:00».
  Число часов до начала рабочего дня без «утра» — после обеда: «в 7» — 19:00.
  После «на» — только «15:00»: «на 2 часа» — длительность.
- Длительность — словари итога дня (`CheckInText.durations`): «15 минут»,
  «полтора часа», «часа на полтора», «на час», «за час», «около часа».
  Диапазон «20–30 минут», «минут 15–20» — по верхней границе. «Через 2 часа»
  — не длительность. Границы 5…720 мин.
- Приоритет: «срочно», «важно», «высокий приоритет», «как можно скорее», «в
  первую очередь», «!!» → высокий; «не срочно», «в последнюю очередь»,
  «когда-нибудь», «если будет время» → низкий («когда-нибудь» ещё и без
  даты).
- Цель: «для/к/по цели X», «цель: X». Имя — до конца фразы или следующего
  параметра; цель находится, если хотя бы половина значимых слов имени есть в
  названии цели («запустить линию» → «Запустить MVP Linea»). Не нашлась —
  слова остаются в названии.
- Сложность: «сложн…» → deep, «легк…», «быстр…» → light; слова не вырезаются.
- Не уверена — пусто (§21): два значения на выбор («завтра или
  послезавтра», «30 минут или час») не берутся оба; время без известного дня
  остаётся в названии; «утром», «вечером», «на днях» — не время.

**Сведение** (`QuickTaskDraft.resolve`). Для каждого параметра: чип →
сказанное → значение по умолчанию, и откуда оно (`Origin`: typed / chosen /
assumed — серый чип). День по умолчанию — сегодня, но только если не назван
ни день, ни срок: срок без дня — задача без дня. «На неделе» — без дня, срок
`TaskDay.endOfWeek` (воскресенье в конце рабочего дня; в субботу и
воскресенье — следующее). Время начала живёт на дне задачи и переезжает
вместе с ним; время, которое уже прошло, без дня — завтра. Длительность не
сказана — `nil`, план берёт свою оценку.

**Цель** (`GoalLinker`). Явная связь — чипом или «для цели …». Иначе
`ConceptGoalMatcher` (§23) находит вероятную цель (`GoalLink.source =
.suggested`) — под чипами «Похоже, относится к: … [Связать]», связывает
человек. Политика `.automatic(minimumScore:)` связывает сама — заложена и
покрыта тестом, по умолчанию выключена (`.suggestOnly`).

**Подписи чипов** (`QuickTaskText`): «Сегодня», «Завтра, 15:00», «Пт, 11 сен»,
«На неделе», «до 18:00», «до пт, 11 сен», «Без даты»; «~30 мин», «~1 ч 30 мин».

**Чипы на экране** (`QuickAddView`, не больше четырёх): «Когда» — Сегодня /
Завтра / На неделе / Выбрать дату (календарь), ниже Срок… (дата и время) и Без
даты; «Сколько» — 15 / 30 / 45 мин / 1 час / Другое (колесо 5 мин … 8 ч);
«Приоритет» — Низкий / Средний / Высокий; «Цель» — только если есть активные
цели: список и Без цели. Серый чип — значение не задавали. Над чипами —
задача так, как Linea её поняла (§21), под ними — подсказка цели (§23).
Создаётся задача только так; карточка задачи — для правки существующей.

## 15. Тип задачи

Решение — ADR-024. Код — `Linea/Core/Intelligence/Classification`, тесты —
`Tests/LineaCoreTests/Classification`.

`TaskKind`: `goal` (шаг к цели), `obligation` (обещано кому-то), `maintenance`
(быт и дела), `routine` (повторяющееся), `incoming` (реакция на пришедшее
извне), `standalone` (разовое личное).

**Классификация** (`TaskClassifier.classify`, детерминированно):
1. `kindOverride` — выбор человека, уверенность 1;
2. `goalID != nil` — `goal`, уверенность 1;
3. словари (`TaskKindWords`): фразы весом 1.5 («разобрать входящие/почту»,
   «ответить на письма», «спланировать неделю» → `routine`; «вынести мусор» →
   `maintenance`), основы весом 1 («оплат», «купи», «врач» → `maintenance`;
   «отправ», «клиент», «встреч», «созвон», «договор» → `obligation`; «ответ»,
   «перезвон», «заявк» → `incoming`; «релиз», «разработ», «запуст», «стратег»
   → `goal`; «ежедневн», «тренировк», «зарядк» → `routine`), слабые: «письмо»,
   «входящ» → `incoming` 0.5, личное («позвон», «мам», «друг», «подар») →
   `standalone` 0.6. Каждое слово голосует за тип один раз;
4. назначенное время — `obligation` +0.5;
5. больший вес побеждает, при равенстве — `incoming > obligation > goal >
   routine > maintenance > standalone`;
6. признаков нет: `demand == .deep` → `goal` (0.45), иначе `standalone` (0.3).

Уверенность: вес ≥ 1.5 → 0.9, ≥ 1 → 0.75, иначе 0.55; второй тип ближе 75 %
веса — минус 0.2. Причина: `chosen`, `linkedGoal`, `keyword(слово)`,
`fixedTime`, `deepWork`, `fallback`.

**Следствия типа.** `TaskEstimate.minutes`: оценка человека (не меньше 5
минут), иначе `typicalMinutes` — цель 60, обязательство/быт/рутина/разовое 30,
входящее 15. Через неё считают длительность планировщик (`PlanDuration`),
обязательства из задач с временем (`CommitmentMapper`) и итог дня
(`CheckInDraft`). Быстрый ввод ставит новой задаче `typicalDemand` (цель —
deep, обязательство и разовое — normal, остальное — light), если сложность не
названа, и показывает `typicalMinutes` серым чипом.

## 16. Движок приоритизации

Решение — ADR-025. Код — `Linea/Core/Intelligence/Priority`
(`PriorityEngine`, `PriorityModels`, `TaskDependencies`), «Сейчас» —
`Linea/Core/Domain/UseCases/NextActionUseCase.swift`, тесты —
`Tests/LineaCoreTests/Priority`.

**Входы** (`PriorityContext`): задача и все задачи (зависимости), цели,
календарь и прочие обязательства (`snapshot.commitments`), текущее время
(`TimeContext`), свободные окна (`window(at:)` — до ближайшего обязательства или
конца рабочего дня), контекст дня (день задачи, рабочий день профиля),
сделанное сегодня (`RecentExecution` — закрытые сегодня задачи), текущее
состояние (`UserState`: энергия и уверенность), калибровка (длительности).

**importance** = `Σ w·f / Σ w` (`EngineConfig.importanceWeight*`). Задача без
цели оценивается по своим признакам: вес цели в сумму не входит и делится
между остальными. У задачи с целью важность — большая из двух оценок: сама по
себе (тип — по словам названия) и как шаг к цели. Связь может только поднять
задачу: goal_id = null ценности не снижает (§23).

| Фактор | Вес | Значение |
|---|---|---|
| priority (`user_priority`) | 0.30 | низкий 0.2 / средний 0.5 / высокий 1.0 |
| goal (`goal_importance`, `goal_deadline`) | 0.25 | `goalAlignment` (§7: срок цели и прогресс) × важность цели: низкая 0.7, средняя 1.0, высокая 1.2; без цели не учитывается |
| deadline (`deadline`, `overdue`) | 0.25 | `urgency` (§7): просрочено — 1, иначе `exp(−slack/36 ч)`; без срока и у задачи со временем — 0.15 |
| kind (`task_type`) | 0.10 | цель 1.0, обязательство 0.9, входящее 0.6, быт 0.5, разовое 0.5, рутина 0.4 |
| dependents (`dependencies`) | 0.05 | сколько открытых задач ждут эту: 0 → 0, 1 → 0.6, 2+ → 1 |
| deferrals (`number_of_deferrals`) | 0.05 | `min(1, переносов / 3)` |

**action** = `gate × fit × (0.5 + 0.5·pull)`:
- `gate` = 0: задача сделана или отменена; ждёт незакрытую (`blockedBy`, с
  учётом того, что план уже поставил раньше); человек сказал «Не сейчас», и
  полтора часа ещё не прошли (§24); у задачи своё время, а сейчас не оно (окно
  — за 10 минут до начала и до конца); сейчас идёт обязательство или рабочий
  день кончился;
- `fit` = `window × (0.4 + 0.6·energyFit)`; `window` (`available_window` против
  `estimated_duration` с калибровкой): хватает — 1, хватает 80 % — 0.8, иначе
  `durationFit` (окно < 15 мин → 0). Без данных о состоянии энергия не
  учитывается (множитель 1);
- `pull` = взвешенное (`actionWeight*`): срок сейчас 0.45 (та же `urgency` в
  этот момент), день 0.35 (сегодня или просрочено — 1, без дня — 0.6, на другой
  день — 0.2), ритм 0.10 (0.9; та же цель закрыта за последние 90 мин — 1;
  сложная задача после 90/150 мин сложной работы сегодня — 0.8/0.6), баланс
  0.10 (задач этого типа закрыто сегодня 0/1/2/3+ → 1/0.95/0.85/0.7).

Ограничения (`ActionLimit`) объясняют низкую уместность: `blocked`,
`notNow(до)`, `shortWindow(осталось, нужно)`, `busy`, `fixedTime`,
`plannedLater`, `lowEnergy` (`energyFit < 0.5`).

**Пример постановки** (закреплён тестами): «Подготовить стратегию», высокий,
90 мин, встреча 15:50–16:20. В 15:30 важность ≈ 0.62, уместность ≈ 0.09 (окно
20 мин из 90); в 16:20 важность та же, уместность ≈ 0.76.

**Где используется.**
- Планировщик (§7): в каждом окне — задача с наибольшим `importance × action`
  при `gate > 0`; зависимые — после завершения по плану того, что они ждут;
  ждущие то, что сегодня не делается, — в отложенные с причиной `blocked`.
  Top-3 — по `importance`. В блоке — `ScoreBreakdown` с пятью факторами и
  `importanceScore`/`actionScore`, `total = importance × action`.
- Кандидаты дня: на сегодня и просроченные, со сроком ≤ +2 дня, плюс до трёх
  без дня — к активной цели или со сроком в ближайшие 7 дней — по `importance`.
- «Сейчас» — одно действие на экране «Сегодня», §17.

**Переносы** (`TaskDeferral`): задача, которую пора было делать (на сегодня
или просрочена), сдвинута на более поздний день или лишилась дня — +1 к
`deferralCount`. Считает `PlanStore` при сохранении: «Переносим» в
напоминании, перенос незакрытого итогом дня, перенос руками.

**Зависимости** (`TaskDependencies`): граф по открытым задачам; ребро, которое
замкнуло бы петлю, не учитывается (по порядку создания); карточка задачи не
предлагает задачи, которые сами ждут эту (`canBlock`).

## 17. Следующее действие

Решение — ADR-027, с этапа 13 — ADR-034. Код —
`Linea/Core/Domain/Models/NextAction.swift`,
`Linea/Core/Domain/UseCases/NextActionUseCase.swift` («Начать», «Завершить»,
«Не сейчас» — `TaskExecutionUseCase`, §24), тесты —
`Tests/LineaCoreTests/Priority` (`NextActionTests`).

**Сущность.** `NextAction` — не задача, а то, что Linea предлагает сделать
сейчас: `option` (задача в роли действия: название и сколько минут отвести),
до трёх `alternatives` («Другое»), `laterTaskID` (важная задача, которой не
хватает окна), `startedAt` (человек уже взялся), `headline` и `reason`
(готовый текст). Ранжированный список задач экран не получает.

**Выбор** (`NextActionUseCase.run`, пересчёт раз в минуту, пока открыт экран
«Сегодня», и после каждого изменения задач):
1. Есть начатое действие (`DayRecord.activeAction`: последний отклик
   `actionStarted`, задача открыта и у неё есть `startedAt`, прошло не больше
   `max(1.5·N, N + 15)` минут из отведённых N) — «сейчас» оно, «в работе».
   Его обязательство при этом из расчёта убирается, чтобы «Другое» видело
   настоящее окно.
2. Идёт обязательство или рабочий день кончился — молчит.
3. Иначе из задач с `action ≥ 0.25`, по `importance × action` (§16):
   выбранная в «Другое» → задача блока принятого плана, который идёт сейчас →
   лучшая. Остальные уместные — «Другое», не больше трёх. Задачи под «Не
   сейчас» уместности не имеют (§24) — их нет ни в «Сейчас», ни в «Другое».
   Выбранная задача уже начата (отведённое время вышло, а её не закрыли) —
   она «в работе» с прежним временем начала: «Начать» заново сбросило бы его.
4. Самая важная задача, которой не хватает окна (не ждущая другую и не на
   другой день), важнее выбранной — «её лучше после».

**Тексты** (`ExplanationMoment.now`, golden-тесты). У каждой рекомендации —
причина, одна короткая фраза (`NowReason`, §22): «До встречи 20 мин — на это
хватит, а «Подготовить стратегию» лучше после встречи.», «Высокий приоритет, а
срок — сегодня вечером.». Окно называется по типу того, что впереди
(`Commitment.kind`, для календаря и задач со временем — по словам названия:
встреча, созвон, планёрка, интервью → встреча; тренировка → тренировка), без
обязательств — «До конца рабочего дня 2 ч», «… лучше завтра».
- ничего не помещается — заголовок «До встречи осталось 10 мин — короткая
  пауза.», ниже ««Подготовить стратегию» лучше начать после встречи.»;
- начато — «Начато в 10:00.».

**Действия человека** (§24).
- «Начать» → у задачи `startedAt`, в день — отклик `actionStarted`
  (`ActionStart`: задача, отведённые минуты, выбрано ли в «Другое», id
  принятого предложения). День, срок и время задачи не меняются. План
  пересобирается и держит время действия занятым: `PlanDayUseCase` добавляет
  обязательство `action-<id задачи>` на отведённые минуты с момента начала,
  если у задачи нет своего времени.
- «Не сейчас» → задача отложена на полтора часа, «Сейчас» — другое.
- «Другое» → «Можно ещё:» с вариантами; тап делает вариант действием
  «сейчас» (выбор живёт в `IntelligenceStore`, пока задача открыта), прежнему
  предложению — ответ «выбрано другое».
- «Завершить» на начатом → задача закрыта, сколько заняло — записано,
  «Сейчас» — следующее.

**Экран.** Подпись «Сейчас» (у начатого — «в работе»), крупно название,
ниже «~15 мин» и причина, кнопки «Начать», «Не сейчас», «Другое»/«Скрыть»; у
начатого — «Завершить» и «Не сейчас». Не влезают в строку — переносятся.
Нечего предлагать — крупно заголовок («… — короткая пауза.»), без кнопок.


## 18. Без даты (входящие)

Решение — ADR-028. Код — `Linea/Core/Intelligence/Inbox/InboxReview.swift`,
`PriorityEngine.inboxPicks`, второй проход в `DecisionEngine.build`, тесты —
`Tests/LineaCoreTests/Inbox`.

**Что во входящих.** Открытая задача без дня, срока и своего времени
(`InboxReview.isInInbox`). Сюда попадает всё, что записали без слов о дне:
`QuickTaskDraft.resolve` по умолчанию даёт `TaskDay.someday`. Неразобранные —
те, у кого нет `inboxReviewedAt`.

**Место в дне** (`PriorityEngine.inboxPicks`, `maxInboxPicks = 2`): задачи из
входящих, кроме низкого приоритета и задач к активной цели (те и так среди
кандидатов дня, §16), по `importance`, при равенстве — давние первыми.
- План: после основной расстановки, если ни одна задача дня не перенесена
  из-за нагрузки или окон, `place` второй раз проходит свободные промежутки
  окон (`DecisionEngine.gaps`, с буфером до и после каждого блока) с той же
  нагрузкой (`budget`). Блоки получают обычные `taskPlanned`; в «три главных»
  не входят (`DecisionEngine.isInboxFiller`); не поместившиеся не попадают в
  `deferredTaskIDs`.
- «Сейчас»: `rankNow` ранжирует кандидатов дня вместе с этими задачами. У
  задачи без дня `day = 0.6` против 1 у задачи на сегодня (§16), поэтому при
  равной важности первой идёт задача дня.

**Разбор.**
- Когда предлагать (`offer`): неразобранных ≥ 3 или одна лежит ≥ 3 дней.
  Текст: «3 задачи без даты — разберём за минуту?».
- Подсказка (`suggestion`), первое подходящее:
  план уже поставил задачу сегодня — «Сегодня»: «Сегодня в 16:30 есть
  свободное время — я уже поставила её туда.»; к активной цели — «На неделе»:
  «Шаг к цели «…» — лучше на этой неделе.»; высокий приоритет — «Завтра»:
  «Важная — лучше не откладывать надолго.»; низкий — «Оставить без даты»:
  «Не срочная — может полежать без даты.»; входящее — «Завтра»: «Ответы лучше
  не держать долго.»; обязательство — «На неделе»: «Обязательство — на этой
  неделе, день подберёт план.»; остальное — «На неделе»: «На этой неделе —
  день подберёт план.».
- Выбор (`apply`): «Сегодня», «Завтра», «На неделе» дают день и срок, как
  одноимённые пункты быстрого ввода (`TaskDay.resolve`); «Оставить без даты»
  оставляет задачу во входящих. В обоих случаях `inboxReviewedAt = now`.
  «Удалить» удаляет задачу.

**Экраны.** Быстрый ввод — серый чип «Без даты». «План» — раздел «Без даты»
под целями (давние первыми, кнопка «Разобрать» — всё «Без даты»,
неразобранные первыми; под задачей, которой план нашёл время, — «Linea нашла
время: сегодня в 16:30») и «Со сроком» после дней. «Сегодня» — предложение
разобрать (только неразобранные). Лист разбора: «1 из 3», название, подсказка,
четыре варианта, «Удалить»; разобрали последнюю — лист закрывается.

## 19. Новая цель

Решение — ADR-029. Код — `Linea/Core/Intelligence/GoalIntake`
(`GoalUnderstanding`, `RuleBasedGoalAnalyzer`), протокол —
`Linea/Core/Domain/Protocols/GoalAnalyzing.swift`, экран —
`Linea/Features/Goals`, тесты — `Tests/LineaCoreTests/GoalIntake`.

**Вход** (`GoalIntakeInput`): название, рассказ (может быть пустым), ответы на
вопросы и пропущенные вопросы.

**Разбор** (`RuleBasedGoalAnalyzer.understand`):
1. Рассказ режется на предложения, предложения — на части по запятой и тире.
   Придаточное («, чтобы …», «, который …», «, чем …») остаётся со своей
   частью. Точка и запятая между цифрами — часть числа.
2. Каждая часть — «Сейчас» или «Результат». Слова желаемого («хочу»,
   «хотим», «нужно», «надо», «чтобы», «будет», «результат», «цель») — это
   результат. Слова того, что есть («уже», «сейчас», «пока», «есть», «идёт»,
   «сделали», «у нас», «у меня»), — это сейчас. Короткие слова сравниваются
   целиком: «пока» — не «показать», «стать» — не «статья». Часть без таких
   слов, но проверяемая — результат; остальные идут за предыдущей частью.
3. Ответ на вопрос о результате — результат, о старте — «Сейчас», даже без
   слов-подсказок.
4. Чистка: у результата снимаются «хочу», «хотим», «нужно», «чтобы», «в итоге»
   и вспомогательные «было», «будет»; у «Сейчас» — «у нас», «у меня»,
   «сейчас». Заглавная буква, части через точку.
5. Признаки успеха — проверяемые куски результата (по «, » и « и »): с числом
   или словом-числом («первые», «тысяча»), со словом, которое можно проверить
   («доступно», «опубликовано», «подключить», «оплата», «релиз», «TestFlight»,
   «App Store»). Нет таких, а в названии есть число («Пробежать 10 км»), —
   признак само название. На вопрос ответили без чисел — ответ и есть признак.
6. Срок — `QuickTaskParser` по частям результата и названию («к 1 декабря»).

**Вопрос** — не больше одного за раз: нет признаков успеха → «Как поймём, что
цель достигнута?»; иначе неизвестно «Сейчас» → «С чего начинаем — что уже
есть?». На вопрос, на который ответили или который пропустили, Linea больше
не спрашивает.

**Пример заказчика** (golden-тест): «Запустить закрытую beta Linea» + «У нас
уже есть рабочий прототип приложения. Сейчас идёт переработка задач и
онбординга. Хотим, чтобы приложение было доступно через TestFlight и
подключить 50 тестировщиков.» → «Сейчас»: «Уже есть рабочий прототип
приложения. Идёт переработка задач и онбординга.»; «Результат»: «Приложение
доступно через TestFlight и подключить 50 тестировщиков.»; признаки:
«Приложение доступно через TestFlight», «Подключить 50 тестировщиков»;
вопросов нет. «Запустить продукт» без рассказа → вопрос о результате.

**Экран.** «Новая цель»: «Чего хочешь достичь?», «Расскажи подробнее»
(необязательно), «Рассказать голосом», «Продолжить». Вопрос — «Уточню одно»:
вопрос, пример ответа, поле, голос, «Продолжить» и «Пропустить». «Я поняла
цель так»: название, срок, «Сейчас», «Результат» и признаки, которых нет в
результате дословно; «Всё верно» и «Изменить». «Изменить» — поля «Цель»,
«Сейчас», «Результат», «Как поймём, что получилось» (по строке), «Срок»;
«Готово» возвращает к «Я поняла цель так». Цель создаётся только на «Всё
верно».

## 20. Перенести задачу

Решение — ADR-030. Код — `Linea/Core/Intelligence/TaskCapture/TaskReschedule.swift`,
тесты — `Tests/LineaCoreTests/TaskCapture/TaskRescheduleTests.swift`.

**Варианты** (`options`), кроме того, где задача уже стоит; у закрытой — нет:
«Сегодня» (если она не на сегодня — в том числе просроченная и без даты),
«Завтра», «На неделе · до вс, 13 сен» (если она не «на неделе»), «На следующей
неделе · пн, 14 сен» (в воскресенье это «Завтра» — пункта нет), «Без даты»
(если у неё есть день или срок). «Выбрать дату…» добавляет экран.

**Что станет с задачей** (`apply`):
- новый день (сегодня, завтра, понедельник, свой) — своё время на тот же час
  нового дня; срок, который был в день задачи или раньше нового дня, — на
  тот же час нового дня; срок впереди остаётся;
- «На неделе» — без дня и своего времени, срок — конец недели
  (`TaskDay.endOfWeek`), если свой срок не раньше и не был в день задачи;
- «Без даты» — без дня, срока и времени, `inboxReviewedAt = now`: человек сам
  решил, разбирать её снова незачем;
- задача из входящих, получившая день или срок, тоже помечается
  разобранной.

Перенос задачи на сегодня или просроченной на более поздний день или в «Без
даты» — `+1` к `deferralCount` (`TaskDeferral`, считает `PlanStore`).

## 21. AI-разбор задачи

Решение — ADR-031. Код — `Linea/Core/Intelligence/TaskCapture`
(`QuickTaskParser`, `QuickTaskDraft`, `TaskOwnership`, `TaskSummaryText`),
модель — `Linea/Core/Domain/Models/TaskField.swift`, тесты —
`Tests/LineaCoreTests/TaskCapture/TaskUnderstandingTests.swift`.

**Пример заказчика** (golden-тест): «Завтра до обеда подготовить КП для
клиента, часа на полтора, высокий приоритет.» → название «Подготовить КП для
клиента», день — завтра, срок — 12:00 завтра, 90 минут, высокий приоритет. На
экране: «Подготовить КП для клиента» и «Завтра · до 12:00 · ~1 ч 30 мин ·
Высокий».

**Правило 1: не уверена — пусто.**
- У каждого значения — опора, кусок строки (`QuickTaskParse.Recognized`).
  `QuickTaskParse.grounded(in:)` выбрасывает значение без опоры и название из
  слов, которых нет в строке (тогда название — строка как есть). Правила так
  работают по построению; модель пройдёт ту же проверку.
- Два значения на выбор — ни одного (`isAlternative`): рядом с «или» (через
  знаки и предлоги «в», «на», «к», «до») по другую сторону значение того же
  рода — день к дню («завтра или в пятницу»), время к времени («в 10 или в
  11»), длительность к длительности, срок к дню или времени. У дня может быть
  своё время: «завтра в 10 или послезавтра» — выбор дня, а «завтра в 10 или в
  11» — выбор времени, день известен. Выражение целиком помечается и по
  кускам не разбирается; слова остаются в названии. «Завтра, или хотя бы
  начать» — не выбор.
- День назван на выбор — время начала и срок «до 18:00» без своего дня тоже
  остаются в названии (`keepTimesOfUnknownDay`): иначе Linea привязала бы их
  к сегодняшнему дню.
- «Утром», «вечером», «днём», «на днях», «потом» — не время и не день.
- Длительность по умолчанию в задачу не пишется (её считает план), «Средний»
  по умолчанию — не выбор человека.

**Правило 2: сказанный приоритет — приоритет человека.**
`QuickTaskResolution.userFields`: поле задано человеком, если сказано словами
или выбрано в чипе (`Origin.typed`/`.chosen`). «Без даты» и «Без цели» в чипе —
тоже его решение. Срок без дня («отчёт к пятнице») — задан срок, а не день.
Сложность — если в строке «сложная», «быстро». Задача хранит набор
(`LineaTask.userFields`, колонка `TaskEntity.userFieldsRaw`; `nil` — задача
сохранена раньше: всё считается заданным человеком).

**Правило 3: правку человека Linea не перезаписывает** (`TaskOwnership`).
- `userEdited(previous:updated:)` — каждое сохранение через `PlanStore`
  (карточка, меню, свайп, «Перенести», разбор «Без даты», итог дня,
  «Переносим» в напоминании) добавляет поменянные поля к заданным
  (`changedFields`: день, срок, время, длительность, приоритет, цель,
  сложность). Отметка «Готово» — не параметр.
- `applying(TaskProposal)` — единственный путь, которым Linea меняет задачу
  сама: берутся только поля, которых человек не задавал.
- `refreshedAfterEdit` — сейчас единственное такое изменение: человек
  переименовал задачу, и сложность, которую подставила Linea, пересчитывается
  по новому названию так же, как при создании (`QuickTaskParser.demand`, иначе
  `TaskKind.typicalDemand`).

**Строка задачи** (`QuickTaskText.summary`): день («Сегодня», «Завтра», «Пт, 11
сен», «На неделе»), «в 15:00», срок («до 12:00» в день задачи, иначе «до пт, 11
сен»), «~1 ч 30 мин», приоритет — через « · », только заданное. Быстрый ввод
показывает над чипами название и строку, когда Linea что-то поняла из слов и
вырезала это из названия (`isUnderstood`; одно «завтра» — нет). В «Плане» под задачей — то же без дня (он в заголовке
раздела) и без приоритета (он справа).

## 22. Причина «Сейчас»

Решение — ADR-032. Код — `Linea/Core/Intelligence/Priority/NowReason.swift`
(`NowReason`, `NowReasoner`), текст — `RuleBasedExplainer.reasonSentence`,
тесты — `Tests/LineaCoreTests/Priority/NowReasonTests.swift`.

У каждого действия «Сейчас» — `Fact.nowReason`. `NowReasoner.reason` берёт
первую подходящую причину:

| № | Когда | Текст |
|---|---|---|
| 1 | важная задача не помещается в окно (`laterAction`) | «До встречи 20 мин — на это хватит, а «Подготовить стратегию» лучше после встречи.» |
| 2 | у задачи своё время | «Назначена на 17:30.» |
| 3 | срок прошёл / день задачи прошёл | «Срок уже прошёл — лучше закрыть сейчас.» / «Её день уже прошёл — лучше закрыть сейчас.» |
| 4 | срок сегодня или завтра | «Высокий приоритет, а срок — сегодня вечером.», «Срок — сегодня до 15:00.», «Срок — завтра.» (с 18:00 — «вечером», завтра вечером — просто «завтра») |
| 5 | идёт её блок в принятом плане | «Сейчас её время по плану.» |
| 6 | окно тесное, но хватает: `нужно ≤ окно ≤ min(120, max(60, 2·нужно))` | «До встречи 35 мин — на эту задачу как раз хватит.» |
| 7 | шаг к главной цели / к другой цели | «Это ближайший шаг по твоей главной цели.» / «Это шаг к цели «…».» |
| 8 | высокий приоритет | «Высокий приоритет — лучше не откладывать.» |
| 9 | её ждут другие | «Без неё не начать «Написать отчёт».» / «Без неё не начать ещё 2 задачи.» |
| 10 | переносили 2+ раза | «Её откладывали уже 3 раза — пора закрыть.» |
| 11 | сложная, а сил хватает (`energyFit ≥ 0.85`) | «Сейчас хорошее время для сложной задачи.» |
| 12 | без даты (из «Без даты») | «У неё нет даты, а свободное время есть сейчас.» |
| 13 | не дольше 15 минут | «Короткая — можно закрыть сразу.» |
| 14 | иначе | «Самое важное из того, что можно сделать сейчас.» |

Главная цель (`NowReasoner.mainGoal`) — самая важная из активных, при равной
важности — с ближним сроком, потом — давняя. Причина считается и для
выбранного в «Другое». Тест проходит весь день по 15 минут и проверяет у
каждой рекомендации: причина есть, одно предложение (названия в «» не в
счёт), до 80 знаков, без «балл», «%», «уверенн», числа — только из фактов.

## 23. Связь задачи с целью

Решение — ADR-033. Код — `Linea/Core/Intelligence/GoalMatcher`
(`ConceptGoalMatcher`, `GoalConcepts`, `GoalLinker.suggestion`), важность —
`PriorityEngine.importance`, экран — `Linea/Components/GoalSuggestionRow.swift`,
тесты — `Tests/LineaCoreTests/GoalMatcher/ConceptGoalMatcherTests.swift`.

**Модель.** `LineaTask.goalID: UUID?` — не больше одной цели.

**Поиск** (`ConceptGoalMatcher.bestMatch`):
1. Понятия текста (`terms`): слово из группы (`GoalConcepts.all`) — понятие
   группы («#launch»), иначе основа слова (`RussianWords.stem`). Служебные,
   числа и общие слова (`genericWords`: «подготовить», «проверить»,
   «написать», «купить»… — сравниваются той же основой) не в счёт.
2. Профиль цели (`profile`): понятия названия — вес 1, результата и признаков
   успеха — 0.9, «Сейчас» и рассказа — 0.7.
3. Оценка: `Σ (вес места × вес понятия) / √(понятий задачи)`. У общего
   глагола («запуск») и слова «Линия» вес понятия 0.6, у остальных — 1.
4. Подсказка — от 0.5; если вторая цель ближе 0.15 — молчит.

Пример заказчика: «Опубликовать сборку в TestFlight» → {запуск, сборка, бета},
«Запустить Линия Beta» → {запуск, Linea, бета} → (0.6 + 1) / √3 ≈ 0.92.
«Запустить стиральную машину» → 0.6 / √3 ≈ 0.35 — молчит.

**Подсказка.** Быстрый ввод — под чипами, пока цель не выбрана и не названа.
Карточка задачи — `GoalLinker.suggestion(for:goals:)`: у открытой задачи без
цели, если человек не выбирал «Без цели» сам (`userFields` содержит `goal`) и
не снял цель только что. «Связать» ставит цель, ничего не нажал — задача без
цели. Автосвязь (`GoalLinker.Policy.automatic`, порог 0.8) выключена.

**Ценность задачи без цели** (§16): вес цели делится между остальными
признаками; с целью — `max(сама по себе, как шаг к цели)`. Тесты: без цели —
среднее своих признаков; связь со слабой целью не опускает срочное дело;
связь с важной горящей целью поднимает; срочное важное без цели важнее
рядового шага к цели.

## 24. Состояния задачи и выполнение

Решение — ADR-034. Код — `Linea/Core/Domain/Models/TaskStatus.swift`,
`TaskSuggestion.swift`, `Linea/Core/Intelligence/Execution` (`TaskLifecycle`,
`SuggestionLog`, `TaskExecutionText`),
`Linea/Core/Domain/UseCases/TaskExecutionUseCase.swift`; в приложении —
`IntelligenceStore.perform`. Тесты — `Tests/LineaCoreTests/Execution`.

**Имена из постановки.**

| Постановка | Linea |
|---|---|
| `inbox` | `TaskStatus.inbox`: без дня, срока и своего времени |
| `planned` | `.planned`: есть день, срок или своё время |
| `suggested` | `.suggested`: «Сейчас» предлагает её, ответа ещё нет |
| `started` | `.started`: есть `startedAt` |
| `completed` | `.completed`: `isDone` |
| `deferred` | `.deferred`: «Не сейчас», `deferredUntil` впереди |
| `cancelled` | `.cancelled`: `cancelledAt` |
| `started_at` | `LineaTask.startedAt` |
| `completed_at` | `LineaTask.completedAt` |
| `actual_duration` | `LineaTask.actualMinutes`, `TaskFinish.actualMinutes` (минуты) |
| `suggestion_id` | `TaskSuggestion.id`; у задачи — `suggestionID`, в откликах — `ActionStart.suggestionID`, `TaskFinish.suggestionID` |
| `accepted` | `TaskSuggestion.accepted`: `true` — `response == .accepted`, `false` — другой ответ, `nil` — ответа ещё нет |

`suggestionID` у задачи бывает только у принятого предложения: «Начать» или
«Завершить» предложенной ставят его вместе с ответом `accepted`, «Не сейчас»
и «Вернуть» снимают.

**Состояние** (`LineaTask.status(at:isSuggested:)`) — первое подходящее:
отменена → сделана → начата → отложена → предложена → запланирована → во
входящих. `isOpen` — не сделана и не отменена.

**Переходы** (`TaskLifecycle`; невозможный — nil, ничего не меняется):

| Действие | Можно | Что меняется |
|---|---|---|
| «Начать» | открытую | `startedAt` = сейчас, «Не сейчас» снимается, `suggestionID` — предложение, если оно было про эту задачу (повторное «Начать» — отсчёт заново) |
| «Завершить», «Готово» | открытую | `isDone`, `completedAt`; `actualMinutes` = от `startedAt`, не меньше 1, больше 720 или назад — nil; не начинали — nil; `suggestionID` — если закрыли предложенную |
| «Не сейчас» | открытую | `deferredUntil` = сейчас + 90 мин; `startedAt`, `suggestionID` снимаются |
| снять с работы | начатую | `startedAt` снимается: «Начать» у другой задачи (в работе одно дело) |
| «Удалить» | не отменённую | `cancelledAt` = сейчас |
| «Вернуть» | сделанную | снова открыта: без `completedAt`, `actualMinutes`, `startedAt`, `suggestionID` |

Итог дня закрывает задачи по-старому: `completedAt` — время итога, сколько
заняло — неизвестно.

**«Не сейчас» в расчётах.** `PriorityEngine.assess`: пока `deferredUntil`
впереди, `gate = 0` и ограничение `notNow(until:)` — уместности нет, «Сейчас»
и «Другое» её не предлагают, о ней не говорят «лучше после встречи».
Планировщик ставит её не раньше `deferredUntil`: если в окне ничего нельзя
начать, а «Не сейчас» кончается в нём же, курсор переходит туда.

**Отменённые** не видны нигде: `PlanStore.tasks` их не отдаёт, движки
пропускают (`isOpen`), вечерний вопрос (`CheckInRequest.relevantTasks`) и
напоминания (`NudgeEngine.due`) о них не спрашивают, «Дальше» прячет их блоки.
В хранилище они остаются.

**Журнал предложений** (`SuggestionLog`, `DayRecord.suggestions`).
`tracking` вызывается при каждом пересчёте «Сейчас», пока экран «Сегодня»
открыт: та же задача — то же предложение; другая — прежнее открытое
закрывается ответом `replaced`, новое записывается с причиной, которую видел
человек (`NowReason`), и пометкой «выбрано в «Другое»». Начатое действие и
пустое «Сейчас» предложений не создают, открытое закрывают. Ответы:

| Что сделал человек | Ответ предложению |
|---|---|
| «Начать» на предложенной; закрыл предложенную | `accepted` |
| «Начать» у другой задачи; выбрал в «Другое» | `otherChosen` |
| «Не сейчас»; «Удалить» предложенную | `declined` |
| Linea сама предложила другое | `replaced` |

`merged(_:with:)` сливает журнал с пересчётом дня, который шёл в это время:
новые предложения дописываются, ответ сильнее его отсутствия.

**Отклики в дне** (`UserFeedback` с энергией, уверенностью, советом по
нагрузке и id плана в этот момент): `actionStarted(ActionStart)`,
`taskFinished(TaskFinish: задача, сколько заняло, сколько отводил план,
предложение)`, `taskNotNow(задача, была ли начата)`, `taskCancelled`,
`taskReopened`. Журнал только дописывается.

**Тексты** (`TaskExecutionText`). Карточка задачи: «В работе с 10:12»
(начата не сегодня — «Начата вчера в 17:05»), «Сделано в 11:05 · за 35 мин»
(вчера — «вчера в 11:05», раньше — «в вс, 6 сен»; не начинали — без «за …»),
«Не сейчас — до 12:30» (после полуночи — «до завтра, 0:45»). Под строкой
списка — только «в работе» и «не сейчас»: сделанную видно по галочке.
