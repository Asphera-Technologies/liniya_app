# Linea Architecture

## Current architecture

Linea is an iOS app built with Swift and SwiftUI. The repository also
contains a Foundation-only **intelligence core** (`Linea/Core`) that is
compiled twice: by Xcode as part of the app target, and by SwiftPM
(`Package.swift`) on Linux/CI for tests. See `Docs/intelligence.md` for the
core's specification and `Docs/decisions.md` for why.

### Layers

```text
Linea/
├── App/          LineaApp (composition root), AppState, RootView
├── Core/         Foundation-only. Domain models, protocols, use cases, engines, connector logic
│   ├── Domain/{Models,Protocols,UseCases}
│   ├── Intelligence/{ContextEngine,StateEngine,DecisionEngine,Priority,FeedbackEngine,LLM,CheckIn,
│   │                 Memory,TaskCapture,Classification,Inbox,GoalIntake,GoalMatcher,GoalProgress,
│   │                 Execution}
│   └── Connectors/   Foundation-only parts of connectors (Nutrition, Calendar)
├── Data/         Apple frameworks allowed: SwiftData entities and Local* repositories,
│                 HealthKit reader, EventKit provider, LLM client (chat), on-device speech (GigaAM, Apple)
├── Platform/     iOS adapters: notifications (nudges), voice recording, diagnostics (OSLog)
├── Features/     SwiftUI screens and view-facing stores (Today, Plan, Health, Nutrition,
│                 Profile, AI, CheckIn, Memory, QuickAdd, Inbox, Goals, Voice)
├── Components/, DesignSystem/   shared UI
├── Networking/   LineaBackend (sample-only protocol; no production API yet)
└── Services/     SampleData / SampleModels for screens not yet backed by real data
HealthKitManager.swift   read-only HealthKit boundary; stays at repo root (explicit pbxproj reference)
Package.swift, Tests/, Scripts/   core build & tests without Xcode
```

Dependency rules:

| Layer | May import | Must not |
|---|---|---|
| `Core/Domain` | Foundation | anything else |
| `Core/Intelligence`, `Core/Connectors` | Foundation, Domain | Apple frameworks; `Date()`, `Calendar.current` (use `TimeContext`) |
| `Data`, `Platform` | Core + SwiftData / HealthKit / EventKit / UserNotifications / Speech / AVFoundation / FoundationModels | Features |
| `Features` | Core types, stores, design system | HealthKit, SwiftData, notification center directly |
| `App` | everything | — |

`Scripts/check-layers.sh` enforces the first two rows; the Docker build
(`Scripts/test-core.sh`) enforces them by construction — Apple frameworks do
not exist on Linux.

### App wiring

The entry point is `LineaApp`. It creates the SwiftData `ModelContainer`,
wires local repositories into `PlanStore`, and injects app-wide dependencies
into the SwiftUI environment. App-wide UI state is held in `AppState`
(Observation). The root navigation is `RootView` with a `TabView` for Today,
Plan, Nutrition, Health, and Profile.

Tasks and goals are domain values (`LineaTask`, `LineaGoal` in
`Core/Domain/Models/PlanModels.swift`) behind `TaskRepository` /
`GoalRepository` protocols (`Core/Domain/Protocols`), implemented by
`LocalTaskRepository` / `LocalGoalRepository` on SwiftData (`Data/`).
`PlanStore` is the view-facing state for tasks and goals.

Health data goes through `HealthKitManager`, a read-only HealthKit boundary;
feature screens never touch `HKHealthStore`. The intelligence core receives
health data only as `ContextSignal`s from a `ContextProvider`.

Concurrency: the project compiles with `SWIFT_DEFAULT_ACTOR_ISOLATION =
MainActor`. Stores and repositories are `@MainActor`; every type in
`Linea/Core` is explicitly `nonisolated` and `Sendable` so engines can run
off the main actor and tests do not need `@MainActor`.

The Xcode project uses Swift, SwiftUI, Observation, SwiftData, Swift
concurrency, HealthKit, EventKit, Speech, AVFoundation; iOS deployment
target 18.0; Xcode 26.6 (Swift 6.3). APIs newer than iOS 18 (Liquid Glass,
`SpeechAnalyzer`) are behind `#available`.

## Intelligence data flow

```text
ContextProviders (HealthKit, Nutrition, later Calendar…)
        ↓  ContextSignal
ContextEngine  → ContextSnapshot (signals + tasks + goals + commitments + profile)
        ↓
StateEngine    → UserState (sleep, recovery, energy, loadAdvice, facts)
        ↓
PriorityEngine → importance + action per task (§16): what matters, what fits now;
                 a task without a goal is judged on its own merits, a goal only lifts it
        ↓
DecisionEngine → DayPlan (time blocks, top-3, recommendations; leftover time — a couple of
                 «Без даты» tasks) + NudgeEngine → Nudges
               + NextActionUseCase → one NextAction on Today: «Начать» / «Не сейчас» /
                 «Другое» (§17), always with one short reason (NowReasoner, §22)
        ↓
Explainer      → Russian text (rule-based always; on-device LLM optional, validated)
        ↓
Today / notifications → UserFeedback → FeedbackEngine → Calibration
```

### Quick task capture

```text
Строка (набрана / надиктована: GigaAM или диктовка клавиатуры)
        ↓  QuickTaskParser — правила на телефоне; «или» — пусто
QuickTaskParse: название, день, срок, время, длительность, приоритет, цель
        ↓  grounded(in:) — у каждого значения опора в словах
        ↓  QuickTaskDraft.resolve — чип > сказанное > по умолчанию
QuickTaskResolution → «как Linea поняла» + чипы + «Похоже, относится к… [Связать]»
        ↓  «Добавить» — сказанное и выбранное становятся полями человека
PlanStore.saveTask → TaskOwnership: правку человека Linea не перезаписывает
```

A title is the only required field; everything else can be changed later in
the task card (ADR-023). Values come only from the words, and what the person
set Linea never overwrites (ADR-031). The likely goal is found by meaning
(`ConceptGoalMatcher`) and only suggested (ADR-033). The «+» next to the command bar and «+ Задача» on
Plan open the same sheet. Nothing said about the day — the task goes to «Без
даты» (ADR-028, §18): no «Когда?», a place is found by the plan or a one-minute
review.

### Task execution

```text
«Начать» / «Завершить» («Готово») / «Не сейчас» / «Удалить» / «Вернуть»
  — «Сейчас», меню строки, карточка задачи, напоминание «Закрываем сейчас»
        ↓  IntelligenceStore.perform — one entry point for every screen
TaskExecutionUseCase: TaskLifecycle (startedAt, completedAt + actualMinutes,
  deferredUntil, cancelledAt) + SuggestionLog (accepted / declined / otherChosen)
        ↓  the day first, then the task: the replan reads the new day
DayRecord: suggestions + feedback (actionStarted, taskFinished, taskNotNow,
  taskCancelled, taskReopened) · PlanStore.saveTasks → replan
```

The seven states (`TaskStatus`) are derived from these fields, never stored
(ADR-034, §24). «Сейчас» logs what it suggests only while Today is open, so a
suggestion means the person saw it. A cancelled task stays in storage but
`PlanStore.tasks` never returns it.

### New goal

```text
«Чего хочешь достичь?» — одна строка (набрана / надиктована: VoiceDictation)
        ↓  GoalLineParser (QuickTaskParser в режиме цели): название, срок, важность
        ↓  GoalClassifier: тип цели (goal_type), сфера, чья цель
        ↓  GoalStructure: числа, этапы, метод прогресса, стадии
QuickGoalResolution → «✦ название · до 15 октября» + чипы (срок, важность,
        прогресс, сфера; чип сильнее сказанного)
        ↓  «Создать цель»                        ↓  «Рассказать подробнее» (по желанию)
PlanStore.saveGoal ← «Всё верно» ← «Я поняла цель так» ← вопрос? ← рассказ
        ↓  GoalRevision: время пересмотра, продвижения — только вперёд
```

A goal is created from one line, like a task (ADR-035, §25); the story,
the clarifying question and «Я поняла цель так» (ADR-029, §19) are optional.
Linea classifies the goal type and picks the progress method and the stages
from it; the person changes them with chips and in the goal card.

### Goal state and progress

```text
LineaGoal: «Сейчас», «Результат», признаки, стадия и стадии, этапы, числа,
           метод прогресса, сфера, чья цель, время пересмотра, журнал
        ↓  GoalProgressEngine (+ задачи цели — только для «значимых действий»)
GoalProgress: value (процент, только честный), completion (для важности
              задач), этапы, числа, стадия, последнее продвижение, действия за 30 дней
        ↓  GoalProgressText
строка цели в «Плане» · карточка цели · TaskScorer.goalAlignment
```

Progress is computed, never stored (ADR-037, §27): a number or weighted
milestones give a percentage; milestones without weights, a manual report
or a qualitative goal never do. Closed tasks never move a goal's
percentage. The goal card edits a fresh copy of the goal (ADR-036, §26).

A team or company goal (`scope`, ADR-038, §28) has two separate measures:
the shared goal's progress and the person's contribution — their own part
(`owner_scope`), their numbers and their tasks. Steps and windows are built
only within the own part (`GoalStepScope`).

### Goal support on Today

```text
DayRecord (план, встречи, ответы дня) + задачи + цели
        ↓  DayComposition: обязательства, быт, другое, шаги к важным целям
GoalBalance — много текущего, 0 шагов, есть 30 минут → «Оставить 30 минут / Не сегодня»
GoalAttention — важная цель 4 дня без действий → «Да / Пока нет»
        ↓  GoalOffer (одна карточка за раз) → IntelligenceStore.answerGoalOffer
отклик goalOffer в день · GoalWindow — задача-окно на 30 минут · «Пока нет» — неделя тишины
```

Support is a question, not a reproach (ADR-039, ADR-040): an answer is
final for the day («Не сегодня») or for a week («Пока нет»).

### Evening check-in and memory

```text
Голос (VoiceRecorder) → SpeechTranscribing (GigaAM на телефоне / диктовка iPhone)
Текст рассказа        → CheckInExtracting (правила на телефоне)
        ↓  CheckInExtraction → CheckInExtractionValidator
CheckInDraft — экран «Проверь», галочки правит человек
        ↓  SubmitCheckInUseCase
задачи (закрыть, перенести) · дневник CheckInEntry · память UserMemory
DayRecord.feedback += dayReport, dayRating → FeedbackEngine (ёмкость дня)

Память + дневник → UserContextBuilder (≤ 900 токенов) → чат
```

The check-in never leaves the phone (ADR-021): GigaAM transcribes, rules parse,
the user confirms (ADR-016). A language model can take the parsing seam
(`FallbackCheckInExtractor.primary`) without touching the screens. The GigaAM
model ships inside the app: the `Speech model` build phase runs
`Scripts/fetch-speech-model.sh`, which puts the pinned, SHA-256-checked files
into `Linea.app/GigaAM` (ADR-022). Memory
follows OpenClaw's layout — curated facts, a daily journal, search with
recency decay, consolidation — but lives on the device (ADR-018). Details:
`Docs/check-in.md`.

## Target architecture

```text
iOS Client (intelligence core on device)
    ↓ optional, with consent
API Client → Linea Backend (LLM proxy, later sync) → AI services
```

`API/openapi.yaml` remains the source of truth for the iOS–backend contract.
In v1 the backend is not required: decisions are made on the device, and
explanations come from templates or the on-device model. The first endpoint
(`POST /v1/explain`) is added to the contract only together with a remote
explainer implementation.

HealthKit and other Apple-specific APIs are handled by the iOS client, as
required by Apple's privacy model; raw health samples never leave the device.
