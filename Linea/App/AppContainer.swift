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
    let intelligenceStore: IntelligenceStore

    /// Local notifications for nudges.
    let nudgeScheduler: NudgeScheduler

    /// Explains decisions in Russian. Templates always; the on-device model is
    /// added here when it is available, and it can only rephrase.
    let explainer: any Explainer

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

        let reader = HealthKitHistoryReader(store: healthKit.healthStore)
        healthHistory = reader
        let scheduler = NudgeScheduler()
        nudgeScheduler = scheduler

        let plan = PlanStore(taskRepository: tasks, goalRepository: goals)
        planStore = plan
        nutritionStore = NutritionStore(repository: nutrition)
        profileStore = UserProfileStore(repository: profile)

        // The intelligence core. This is the whole registration surface:
        // connectors, state analyzers and rules are named exactly once, here.
        let renderer = RuleBasedExplainer()
        explainer = FallbackExplainer(primary: nil, fallback: renderer)

        let engineConfig = EngineConfig.default
        let stateEngine = StateEngine(
            analyzers: StateEngine.defaultAnalyzers + [NutritionFuelAnalyzer()],
            config: engineConfig
        )
        let decisionEngine = DecisionEngine(
            rules: [DayBriefRule(), NutritionRule()],
            renderer: renderer,
            config: engineConfig
        )
        let nudgeEngine = NudgeEngine(renderer: renderer, config: engineConfig)
        // Registered connectors. Nutrition is added per refresh by the store,
        // because its profile changes; see Docs/connectors.md.
        let contextEngine = ContextEngine(providers: [
            HealthKitContextProvider(reader: reader),
        ])

        intelligenceStore = IntelligenceStore(
            planDay: PlanDayUseCase(
                contextEngine: contextEngine,
                stateEngine: stateEngine,
                decisionEngine: decisionEngine,
                nudgeEngine: nudgeEngine,
                explainer: explainer,
                config: engineConfig
            ),
            acceptPlan: AcceptPlanUseCase(nudgeEngine: nudgeEngine, config: engineConfig),
            checkIn: CheckInUseCase(nudgeEngine: nudgeEngine, config: engineConfig),
            records: records,
            calibrations: calibration,
            profiles: profile,
            nutritionRepository: nutrition,
            history: reader,
            planStore: plan,
            scheduler: scheduler,
            config: engineConfig
        )

        // Any change to tasks, goals, the profile or nutrition rebuilds the day.
        let store = intelligenceStore
        plan.onPlanInputsChanged = { [weak store] in await store?.refresh(reason: .inputsChanged) }
        nutritionStore.onPlanInputsChanged = { [weak store] in await store?.refresh(reason: .inputsChanged) }
        profileStore.onPlanInputsChanged = { [weak store] in await store?.refresh(reason: .inputsChanged) }
    }

    /// The user's real clock — nothing below the App layer creates one.
    var time: TimeContext { .live }
}
