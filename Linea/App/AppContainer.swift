//
//  AppContainer.swift
//  Linea
//
//  The composition root. This is the ONLY place that knows which connectors,
//  analyzers and rules exist, and the only place that reads the real clock.
//  Adding a data source (calendar, location, screen time) means adding a line
//  here — see Docs/connectors.md — never touching the intelligence core.
//

import Foundation
import SwiftData
import HealthKit

@MainActor
final class AppContainer {

    let modelContainer: ModelContainer

    // Repositories (protocols live in Core/Domain/Protocols)
    let taskRepository: any TaskRepository
    let goalRepository: any GoalRepository
    let dayRecordRepository: any DayRecordRepository
    let calibrationRepository: any CalibrationRepository
    let userProfileRepository: any UserProfileRepository
    let nutritionRepository: any NutritionRepository

    // Health boundary shared by the UI and the connector, so both see one store.
    let healthKit: HealthKitManager
    let healthHistory: HealthKitHistoryReader

    // View-facing stores
    let planStore: PlanStore
    let nutritionStore: NutritionStore
    let profileStore: UserProfileStore

    /// Local notifications for nudges.
    let nudgeScheduler: NudgeScheduler

    init(modelContainer: ModelContainer, healthKit: HealthKitManager) {
        self.modelContainer = modelContainer
        self.healthKit = healthKit

        let context = modelContainer.mainContext
        let tasks = LocalTaskRepository(context: context)
        let goals = LocalGoalRepository(context: context)
        let records = LocalDayRecordRepository(context: context)
        let calibration = LocalCalibrationRepository(context: context)
        let profile = LocalUserProfileRepository(context: context)
        let nutrition = LocalNutritionRepository(context: context)

        taskRepository = tasks
        goalRepository = goals
        dayRecordRepository = records
        calibrationRepository = calibration
        userProfileRepository = profile
        nutritionRepository = nutrition

        healthHistory = HealthKitHistoryReader(store: healthKit.healthStore)
        nudgeScheduler = NudgeScheduler()

        planStore = PlanStore(taskRepository: tasks, goalRepository: goals)
        nutritionStore = NutritionStore(repository: nutrition)
        profileStore = UserProfileStore(repository: profile)
    }

    /// Context providers in registration order. A new connector is one more
    /// line here; the engines subscribe to signal kinds, not to providers.
    func contextProviders(nutrition profile: NutritionProfile?, meals: [MealLog]) -> [any ContextProvider] {
        [
            HealthKitContextProvider(reader: healthHistory),
            NutritionContextProvider(profile: profile, meals: meals),
        ]
    }

    /// The user's real clock — nothing below the App layer creates one.
    var time: TimeContext { .live }
}
