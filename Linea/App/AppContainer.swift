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
import EventKit

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
    let checkInRepository: any CheckInRepository
    let memoryRepository: any MemoryRepository

    // Health boundary shared by the UI and the connector, so both see one store.
    let healthKit: HealthKitManager
    let healthHistory: HealthKitHistoryReader

    // View-facing stores
    let planStore: PlanStore
    let nutritionStore: NutritionStore
    let profileStore: UserProfileStore
    let intelligenceStore: IntelligenceStore
    /// Память Linea и дневник итогов дня.
    let memoryStore: MemoryStore
    /// «Итог дня»: запись, распознавание, разбор, сохранение.
    let checkInStore: CheckInStore
    /// Модель распознавания русской речи на телефоне; скачивается по кнопке.
    let localSpeechModel: LocalSpeechModel

    /// Local notifications for nudges.
    let nudgeScheduler: NudgeScheduler

    /// One calendar store for the app: the connector reads through it and the
    /// Profile screen asks for access through it.
    let eventStore: EKEventStore

    /// Explains decisions in Russian. Templates always; the cloud model only
    /// rephrases, and only when a key is configured and the user agreed.
    let explainer: any Explainer

    /// Свободный разговор на экране Linea AI. `nil`, если ключ не настроен.
    let assistant: AssistantService?

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
        let checkIns = LocalCheckInRepository(context: context)
        let memoryDocuments = LocalMemoryRepository(context: context)

        taskRepository = tasks
        goalRepository = goals
        dayRecordRepository = records
        calibrationRepository = calibration
        userProfileRepository = profile
        nutritionRepository = nutrition
        checkInRepository = checkIns
        memoryRepository = memoryDocuments

        let events = EKEventStore()
        eventStore = events

        let reader = HealthKitHistoryReader(store: healthKit.healthStore)
        healthHistory = reader
        let scheduler = NudgeScheduler()
        nudgeScheduler = scheduler

        let plan = PlanStore(taskRepository: tasks, goalRepository: goals)
        planStore = plan
        nutritionStore = NutritionStore(repository: nutrition, catalog: VkusVillClient())
        profileStore = UserProfileStore(repository: profile)
        let memory = MemoryStore(memoryRepository: memoryDocuments, checkInRepository: checkIns)
        memoryStore = memory

        // The intelligence core. This is the whole registration surface:
        // connectors, state analyzers and rules are named exactly once, here.
        let renderer = RuleBasedExplainer()
        // Ключ приходит из Info.plist (см. Docs/secrets.md). Нет ключа —
        // приложение полностью работает на шаблонах.
        let modelClient = AISettings.configuration.map { LanguageModelClient(configuration: $0) }
        assistant = modelClient.map { AssistantService(client: $0) }
        explainer = FallbackExplainer(
            primary: modelClient.map { RemoteExplainer(client: $0) },
            fallback: renderer
        )

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

        let intelligence = IntelligenceStore(
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
            config: engineConfig,
            calendarProvider: { CalendarContextProvider(store: events) },
            assistant: assistant,
            memory: memory
        )
        intelligenceStore = intelligence

        // Итог дня — целиком на телефоне, наружу не уходит ничего (ADR-021).
        // Голос распознаёт модель GigaAM, если скачана, иначе системная
        // диктовка; модель не справилась — тоже диктовка. Рассказ разбирают
        // правила; языковая модель на телефоне, если появится, встанет в
        // `primary` — экрану ничего менять не придётся.
        let localModel = LocalSpeechModel()
        localSpeechModel = localModel
        checkInStore = CheckInStore(
            recorder: VoiceRecorder(),
            planStore: plan,
            intelligence: intelligence,
            memory: memory,
            makeTranscriber: {
                let dictation = AppleSpeechTranscriber()
                guard localModel.isReady else { return dictation }
                return FallbackSpeechTranscriber(primary: LocalSpeechTranscriber(modelFolder: localModel.folder), fallback: dictation)
            },
            extractor: FallbackCheckInExtractor(primary: nil)
        )

        // Any change to tasks, goals, the profile or nutrition rebuilds the day.
        let store = intelligence
        plan.onPlanInputsChanged = { [weak store] in await store?.refresh(reason: .inputsChanged) }
        nutritionStore.onPlanInputsChanged = { [weak store] in await store?.refresh(reason: .inputsChanged) }
        profileStore.onPlanInputsChanged = { [weak store] in await store?.refresh(reason: .inputsChanged) }
    }

    /// The user's real clock — nothing below the App layer creates one.
    var time: TimeContext { .live }
}
