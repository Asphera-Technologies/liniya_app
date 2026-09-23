//
//  LineaApp.swift
//  Linea
//
//  Created by Fedor Sherstnev on 28.08.2026.
//
//  App entry point. It builds the SwiftData container and hands everything
//  else to `AppContainer` — the single place where repositories, connectors,
//  engines and the real clock are wired together. The UI depends on stores and
//  protocols, never on SwiftData or HealthKit directly, so a remote repository
//  or a new data source can be swapped in here alone.
//

import SwiftUI
import SwiftData

@main
struct LineaApp: App {
    /// Receives answers to notification buttons (see AppDelegate).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// App-wide UI state (ambient AI surface, etc.).
    @State private var appState = AppState()

    /// The single read-only HealthKit boundary, shared across screens.
    @State private var healthKit: HealthKitManager

    @State private var container: AppContainer

    init() {
        let modelContainer: ModelContainer
        do {
            modelContainer = try ModelContainer(for: Schema(LineaSchema.models))
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
        let health = HealthKitManager()
        _healthKit = State(initialValue: health)
        _container = State(initialValue: AppContainer(modelContainer: modelContainer, healthKit: health))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(healthKit)
                .environment(container.planStore)
                .environment(container.nutritionStore)
                .environment(container.profileStore)
                .environment(container.intelligenceStore)
                .environment(container.memoryStore)
                .environment(container.checkInStore)
                .tint(LineaColor.ink)
                .onAppear {
                    appDelegate.intelligence = container.intelligenceStore
                    appDelegate.appState = appState
                }
        }
        .modelContainer(container.modelContainer)
    }
}
