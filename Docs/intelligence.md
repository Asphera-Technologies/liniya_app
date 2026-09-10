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
│   │   ├── DecisionEngine/   TaskScorer, FreeWindows, DayPlanner, правила, NudgeEngine
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

**Cold start / деградация:** HealthKit не подключён → компонентов нет,
`energy 0.5`, `loadAdvice unknown`, factor `energyFit` исключается из scoring
с перераспределением веса, текст «Не вижу данных Apple Health». Дни 1–6 →
абсолютные значения, «собираю базу: день N из 7», без слова «обычно».

## 7. Decision Engine

Кандидаты: открытые задачи с `date == today`, просроченные, с `deadline ≤
today + 2 дня`, а также без даты, но привязанные к активной цели (не более 3
по score). Задачи с `scheduledStart` — обязательства, в жадный проход не
входят, но получают score и могут быть в Top-3.

**Score** (все компоненты 0…1, веса из `EngineConfig`):

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

**Top-3:** три задачи с наибольшим score среди поставленных (включая
фиксированные) → `topTaskIDs`, `isTop`. Факт `topTaskCount(N)`.
`hardWorkDeadline(12:00)` — если задача с максимальным demand поставлена
целиком до 12:00.

**PlanRule** (после расстановки): `LoadAdjustmentRule` (при `reduce` →
`Recommendation(.loadAdjustment)`), `NutritionRule` (см. §10). Правила
детерминированы и могут добавлять блоки `.meal/.rest`.

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
- `capacityFactor = 0.8·prev + 0.2·clamp(completed/planned, 0.5, 1.1)` по дням
  с принятым планом и ≥ 30 запланированных минут;
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
- `Fixtures/WowFixture` — сценарий брифа с явными числами: Europe/Moscow,
  2026-09-09, сон 6:03 (21 780 с) при обычных 7:13, HRV 38 при обычных 52,
  RHR 58 при 54, задачи A/B/C, цель «Запустить MVP Linea», обед 13:00,
  созвон 15:50, тренировка 17:00 — так «1 ч 20 мин» получается из данных;
- `SleepAnalyzerTests` (два источника, только inBed, через полночь),
  `BaselineTests`, `StateEngineTests` (reduce, cold start 0/2/3/7 дней,
  отсутствие HRV), `TaskScorerTests`, `DayPlannerTests` (порядок A-C-B,
  блоки не пересекают обязательства, детерминизм), `NudgeEngineTests`
  (14:30 → 80 мин; done → пусто; 23:00 → пусто), `FeedbackEngineTests`,
  `ExplainerTests` (golden-строки), `UseCaseTests` (end-to-end утро → 14:30
  → вечер), `CodableTests` (round-trip DayRecord).

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
