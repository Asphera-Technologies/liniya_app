# Linea Architecture

## Current architecture

Linea is an iOS app built with Swift and SwiftUI.

The current app entry point is `LineaApp`. It creates a SwiftData `ModelContainer`, wires local repositories, and injects shared dependencies into the SwiftUI environment.

App-wide UI state is held in `AppState` using Observation. The root navigation is `RootView`, which uses a SwiftUI `TabView` for Today, Plan, Nutrition, Health, and Profile.

Tasks and goals use domain models in `Models/PlanModels.swift`. Persistence is kept behind `TaskRepository` and `GoalRepository` protocols. The current implementations, `LocalTaskRepository` and `LocalGoalRepository`, are backed by SwiftData entities in `Persistence/`.

`PlanStore` is the view-facing state for tasks and goals. It depends on repository protocols, exposes domain values to SwiftUI, and uses async methods for loading and mutations.

Health data is handled through `HealthKitManager`, a read-only HealthKit boundary. Feature screens do not access `HKHealthStore` directly. HealthKit authorization and metric reads stay in the iOS client.

Networking is currently represented by the `LineaBackend` protocol and `SampleBackend`. This layer is sample-only and does not define production endpoints, authentication, or payload shapes. There are no direct `URLSession` calls or production API client implementation in the current Swift code.

The Xcode project uses:

- Swift
- SwiftUI
- Observation
- SwiftData
- Swift concurrency with async/await
- HealthKit
- iOS deployment target 26.5

## Target architecture

```text
iOS Client
    ↓
API Client
    ↓
Linea Backend
    ↓
Database / AI services / integrations
```

`API/openapi.yaml` is the source of truth for the iOS-backend contract. Backend and iOS changes that affect requests, responses, authentication, or error shapes should start there.

HealthKit and other Apple-specific APIs are handled directly by the iOS client where required by the architecture and Apple's privacy model.
