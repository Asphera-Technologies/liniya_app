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
│   ├── Intelligence/{ContextEngine,StateEngine,DecisionEngine,FeedbackEngine,LLM,CheckIn,Memory}
│   └── Connectors/   Foundation-only parts of connectors (Nutrition, Calendar)
├── Data/         Apple frameworks allowed: SwiftData entities and Local* repositories,
│                 HealthKit reader, EventKit provider, LLM and speech clients (xAI, Apple Speech)
├── Platform/     iOS adapters: notifications (nudges), voice recording, diagnostics (OSLog)
├── Features/     SwiftUI screens and view-facing stores (Today, Plan, Health, Nutrition,
│                 Profile, AI, CheckIn, Memory)
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
DecisionEngine → DayPlan (time blocks, top-3, recommendations) + NudgeEngine → Nudges
        ↓
Explainer      → Russian text (rule-based always; on-device LLM optional, validated)
        ↓
Today / notifications → UserFeedback → FeedbackEngine → Calibration
```

### Evening check-in and memory

```text
Голос (VoiceRecorder) → SpeechTranscribing (xAI с согласия / iPhone)
Текст рассказа        → CheckInExtracting (Grok с согласия / правила)
        ↓  CheckInExtraction → CheckInExtractionValidator
CheckInDraft — экран «Проверь», галочки правит человек
        ↓  SubmitCheckInUseCase
задачи (закрыть, перенести) · дневник CheckInEntry · память UserMemory
DayRecord.feedback += dayReport, dayRating → FeedbackEngine (ёмкость дня)

Память + дневник → UserContextBuilder (≤ 900 токенов) → чат, разбор итога
```

The model reads, the code decides, the user confirms (ADR-016). Memory
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
