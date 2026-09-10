//
//  LineaApp.swift
//  Linea
//
//  Created by Fedor Sherstnev on 28.08.2026.
//
//  Composition root: builds the SwiftData container, wires the local
//  repositories into `PlanStore`, and injects app-wide dependencies. The UI
//  depends on `PlanStore` + repository protocols — never SwiftData directly —
//  so a remote repository / sync layer can be swapped in later here alone.
//

import SwiftUI
import SwiftData

@main
struct LineaApp: App {
    /// App-wide UI state (ambient AI surface, etc.).
    @State private var appState = AppState()

    /// The single read-only HealthKit boundary, shared across screens.
    @State private var healthKit = HealthKitManager()

    /// Tasks & goals store, backed by local SwiftData repositories.
    @State private var planStore: PlanStore

    private let modelContainer: ModelContainer

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: TaskEntity.self, GoalEntity.self)
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
        modelContainer = container

        let taskRepository = LocalTaskRepository(context: container.mainContext)
        let goalRepository = LocalGoalRepository(context: container.mainContext)
        _planStore = State(
            initialValue: PlanStore(
                taskRepository: taskRepository,
                goalRepository: goalRepository
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(healthKit)
                .environment(planStore)
                .tint(LineaColor.ink)
        }
    }
}
