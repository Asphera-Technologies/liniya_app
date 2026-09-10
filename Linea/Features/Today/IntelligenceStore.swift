//
//  IntelligenceStore.swift
//  Linea
//
//  The view-facing face of the intelligence core: it loads what the engines
//  need, runs the use cases, keeps the result for the screens and persists the
//  day. Same shape as `PlanStore` — protocols in, domain values out.
//
//  Everything it exposes is already decided and already worded; the views only
//  arrange it. That is what keeps the golden tests meaningful: what the tests
//  assert is literally what the screen shows.
//

import Foundation
import Observation

@Observable
@MainActor
final class IntelligenceStore {

    enum RefreshReason {
        /// A screen appeared or the app came to the foreground.
        case appeared
        /// Pull to refresh.
        case manual
        /// Tasks, goals, profile or nutrition changed.
        case inputsChanged
    }

    // MARK: Published state

    private(set) var state: UserState?
    private(set) var plan: DayPlan?
    private(set) var dueNudge: Nudge?
    private(set) var sleepInsight: SleepInsight = .empty
    private(set) var calibration: Calibration = .default
    private(set) var providerStatuses: [ProviderID: ProviderStatus] = [:]
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?

    // MARK: Dependencies

    private let planDayUseCase: PlanDayUseCase
    private let acceptPlanUseCase: AcceptPlanUseCase
    private let checkInUseCase: CheckInUseCase
    private let respondUseCase: RespondToNudgeUseCase
    private let ratingUseCase: RecordDayRatingUseCase
    private let records: any DayRecordRepository
    private let calibrations: any CalibrationRepository
    private let profiles: any UserProfileRepository
    private let nutritionRepository: any NutritionRepository
    private let history: any HealthHistorySource
    private let planStore: PlanStore
    private let scheduler: NudgeScheduler?
    private let timeProvider: @MainActor () -> TimeContext
    private let config: EngineConfig
    /// Built on demand so the connector only exists while the user keeps the
    /// calendar switched on. Nil in previews and tests.
    private let calendarProvider: (@MainActor () -> any ContextProvider)?

    /// Cached daily aggregates, so a foreground refresh does not re-read weeks
    /// of HealthKit every time.
    private var historyCache: [DailyHealthSummary] = []
    private var historyLoadedAt: Date?
    private var record: DayRecord?

    init(
        planDay: PlanDayUseCase,
        acceptPlan: AcceptPlanUseCase,
        checkIn: CheckInUseCase,
        respond: RespondToNudgeUseCase = RespondToNudgeUseCase(),
        recordRating: RecordDayRatingUseCase = RecordDayRatingUseCase(),
        records: any DayRecordRepository,
        calibrations: any CalibrationRepository,
        profiles: any UserProfileRepository,
        nutritionRepository: any NutritionRepository,
        history: any HealthHistorySource,
        planStore: PlanStore,
        scheduler: NudgeScheduler? = nil,
        config: EngineConfig = .default,
        time: @escaping @MainActor () -> TimeContext = { .live },
        calendarProvider: (@MainActor () -> any ContextProvider)? = nil
    ) {
        self.planDayUseCase = planDay
        self.acceptPlanUseCase = acceptPlan
        self.checkInUseCase = checkIn
        self.respondUseCase = respond
        self.ratingUseCase = recordRating
        self.records = records
        self.calibrations = calibrations
        self.profiles = profiles
        self.nutritionRepository = nutritionRepository
        self.history = history
        self.planStore = planStore
        self.scheduler = scheduler
        self.config = config
        self.timeProvider = time
        self.calendarProvider = calendarProvider
    }

    var time: TimeContext { timeProvider() }

    // MARK: - Refresh

    func refresh(reason: RefreshReason) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let time = self.time
        do {
            await planStore.load()
            let profile = try await profiles.load()
            calibration = try await calibrations.load()
            let nutrition = try await nutritionRepository.profile()
            let meals = try await nutritionRepository.meals(on: time.dayInterval(containing: time.now))
            let existing = try await records.record(for: time.today)
            let previousAdvice = try await previousLoadAdvice(before: time.today)
            await loadHistoryIfNeeded(time: time)

            let output = await planDayUseCase.run(
                PlanDayUseCase.Input(
                    time: time,
                    tasks: planStore.tasks,
                    goals: planStore.goals,
                    profile: profile,
                    nutrition: nutrition,
                    meals: meals,
                    history: historyCache,
                    calibration: calibration,
                    previousLoadAdvice: previousAdvice,
                    existing: existing,
                    historyDays: 0,
                    // Connectors whose data or availability changes between
                    // refreshes are built here rather than registered once.
                    additionalProviders: connectors(nutrition: nutrition, meals: meals, profile: profile)
                )
            )

            apply(output.record)
            sleepInsight = output.insight
            try await records.save(output.record)
            await evaluateNudges(time: time)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func connectors(nutrition: NutritionProfile?, meals: [MealLog], profile: UserProfile) -> [any ContextProvider] {
        var providers: [any ContextProvider] = [NutritionContextProvider(profile: nutrition, meals: meals)]
        if profile.isCalendarEnabled, let calendarProvider {
            providers.append(calendarProvider())
        }
        return providers
    }

    /// Health history is read once a day: HealthKit is the source of truth,
    /// but four weeks of samples is not something to re-read on every tap.
    private func loadHistoryIfNeeded(time: TimeContext) async {
        if let loadedAt = historyLoadedAt, time.isSameDay(loadedAt, time.now), !historyCache.isEmpty { return }
        do {
            historyCache = try await history.dailySummaries(days: config.baselineWindowDays, before: time.today, time: time)
            historyLoadedAt = time.now
        } catch {
            // No history is a degraded mode, not a failure: the day is still planned.
            historyCache = []
        }
    }

    private func previousLoadAdvice(before day: Date) async throws -> LoadAdvice? {
        let time = self.time
        let yesterday = time.adding(days: -1, to: day)
        return try await records.record(for: yesterday)?.state?.loadAdvice
    }

    private func apply(_ record: DayRecord) {
        self.record = record
        state = record.state
        plan = record.plan
        providerStatuses = record.snapshot?.providerStatuses ?? [:]
    }

    // MARK: - Intents

    /// «Принять план»: freeze it and schedule the day's nudges.
    func acceptPlan() async {
        guard let record else { return }
        let time = self.time
        let output = acceptPlanUseCase.run(record: record, calibration: calibration, time: time)
        apply(output.record)
        try? await records.save(output.record)

        if let scheduler {
            scheduler.registerCategories()
            if await scheduler.requestAuthorizationIfNeeded() {
                await scheduler.sync(output.nudges, time: time)
            }
        }
        await evaluateNudges(time: time)
    }

    func respond(to nudge: Nudge, action: NudgeAction) async {
        guard let record else { return }
        let time = self.time
        let output = respondUseCase.run(record: record, nudge: nudge, action: action, time: time)
        apply(output.record)
        try? await records.save(output.record)
        dueNudge = nil

        switch output.effect {
        case .deferTask(let taskID, let day):
            if let task = planStore.tasks.first(where: { $0.id == taskID }) {
                await planStore.deferTask(task, to: day)
            }
            await refresh(reason: .inputsChanged)
        case .replan:
            await refresh(reason: .inputsChanged)
        case .rateDay, .none:
            await evaluateNudges(time: time)
        }
    }

    func rateDay(_ rating: DayRating) async {
        guard let record else { return }
        let time = self.time
        let history = (try? await records.records(since: time.adding(days: -30, to: time.today))) ?? []
        let output = ratingUseCase.run(
            record: record, rating: rating, history: history,
            previous: calibration, time: time
        )
        apply(output.record)
        calibration = output.calibration
        try? await records.save(output.record)
        try? await calibrations.save(output.calibration)
        dueNudge = nil
        await scheduler?.cancelAll()
    }

    func resetCalibration() async {
        calibration = .default
        try? await calibrations.save(.default)
    }

    /// A recommendation's button was tapped on Today.
    func perform(_ action: RecommendationAction) async {
        switch action {
        case .markMealEaten(let kind):
            try? await nutritionRepository.log(MealLog(at: time.now, kind: kind))
            await refresh(reason: .inputsChanged)
        case .acceptPlan:
            await acceptPlan()
        case .deferTask(let taskID):
            if let task = planStore.tasks.first(where: { $0.id == taskID }) {
                await planStore.deferTask(task, to: time.adding(days: 1, to: time.today))
            }
        case .openTask, .dismiss:
            break
        }
    }

    // MARK: - Nudges

    private func evaluateNudges(time: TimeContext) async {
        guard let record else { return }
        let output = checkInUseCase.run(record: record, tasks: planStore.tasks, calibration: calibration, time: time)
        dueNudge = output.due
        if let scheduler, plan?.status == .accepted {
            await scheduler.sync(output.scheduled, time: time)
        }
    }

    /// A notification action came back while the app was closed.
    func handleNotification(_ response: NudgeScheduler.NotificationResponse) async {
        await refresh(reason: .appeared)
        switch response {
        case .finishNow(let nudgeID, let taskID):
            guard let nudge = record?.nudges.first(where: { $0.id == nudgeID }) ?? dueNudge else { return }
            await respond(to: nudge, action: .finishNow(taskID: taskID))
        case .deferTask(let nudgeID, let taskID):
            guard let nudge = record?.nudges.first(where: { $0.id == nudgeID }) ?? dueNudge else { return }
            await respond(to: nudge, action: .deferTask(taskID: taskID))
        case .rate(let rating):
            await rateDay(rating)
        case .open:
            break
        }
    }

    // MARK: - Derived for the UI

    var brief: Recommendation? { plan?.brief }

    /// Evidence lines under the brief («Сон 6:03 — на 1 ч 10 мин меньше обычного.»).
    var reasons: [String] {
        guard let brief else { return [] }
        let request = ExplanationRequest(
            moment: .morning, facts: brief.facts,
            localeIdentifier: time.locale.identifier,
            hour: time.timeOfDay(of: time.now).hour,
            timeZoneIdentifier: time.timeZone.identifier
        )
        return RuleBasedExplainer().render(request).reasons
    }

    var canAcceptPlan: Bool { plan?.status == .proposed && !(plan?.blocks.isEmpty ?? true) }

    var topTask: LineaTask? {
        guard let id = plan?.topTaskIDs.first else { return nil }
        return planStore.tasks.first { $0.id == id }
    }

    /// What is still ahead: everything that has not ended yet, plus tasks that
    /// were due earlier and are still open. A meal that already happened is not
    /// news; an unfinished task is.
    var visibleBlocks: [PlanBlock] {
        let now = time.now
        return (plan?.blocks ?? [])
            .filter { block in
                if block.end > now { return true }
                return block.taskID != nil && !isDone(block)
            }
            .sorted { $0.start < $1.start }
    }

    func isDone(_ block: PlanBlock) -> Bool {
        guard let taskID = block.taskID else { return false }
        return planStore.tasks.first { $0.id == taskID }?.isDone ?? false
    }

    var advice: [Recommendation] {
        (plan?.recommendations ?? [])
            .filter { $0.kind != .dayBrief }
            .sorted { $0.priority > $1.priority }
    }

    var isEveningReviewDue: Bool {
        guard let record, record.rating == nil, plan?.status == .accepted else { return false }
        let profile = record.snapshot?.profile ?? .default
        return time.timeOfDay(of: time.now) >= profile.eveningCheckIn
    }

    /// Short tag next to the section titles: «нагрузку снижаем», «база 3/7».
    var stateTag: String? {
        guard let state else { return nil }
        if let progress = state.baselineProgress, !progress.isComplete {
            return "база \(progress.days)/\(progress.needed)"
        }
        switch state.loadAdvice {
        case .reduce: return "разгружаем"
        case .push: return "есть запас"
        case .normal: return nil
        case .unknown: return "без данных"
        }
    }

    var planTag: String? {
        switch plan?.status {
        case .accepted: return "план принят"
        case .proposed: return "предложение"
        default: return nil
        }
    }

    /// Rows for Profile → «Подключения».
    var connections: [Connection] {
        providerStatuses
            .filter { $0.key != .healthKit }
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { Connection(id: $0.key.rawValue, title: Self.title(for: $0.key), statusText: Self.text(for: $0.value)) }
    }

    struct Connection: Identifiable {
        let id: String
        let title: String
        let statusText: String
    }

    var explainerTitle: String {
        switch plan?.explainerID {
        case "on-device": return "На устройстве"
        case nil: return "Шаблоны"
        default: return "Шаблоны"
        }
    }

    /// Answers the three starter prompts on the AI screen from what is already computed.
    func answer(to question: String) -> String {
        let lowercased = question.lowercased()
        if lowercased.contains("сон") || lowercased.contains("спал") {
            return sleepAnswer
        }
        if lowercased.contains("план") || lowercased.contains("сегодня") {
            return brief?.message ?? "План на сегодня ещё не собран — открой «Сегодня»."
        }
        if lowercased.contains("обед") || lowercased.contains("еда") || lowercased.contains("приготовить") {
            return advice.first { $0.kind == .meal || $0.kind == .preWorkoutMeal }?.message
                ?? "Пока нечего подсказать по еде — заполни профиль питания."
        }
        return "Пока я отвечаю только про план, сон и еду. Свободный разговор появится позже."
    }

    private var sleepAnswer: String {
        guard let average = sleepInsight.weekAverageSeconds else {
            return "Пока не вижу данных о сне."
        }
        var parts = ["За неделю в среднем \(RussianText.hoursMinutes(seconds: average))."]
        if sleepInsight.canCompare, let usual = sleepInsight.usualSeconds {
            parts.append("Обычно \(RussianText.hoursMinutes(seconds: usual)).")
        } else if let progress = sleepInsight.baselineProgress {
            parts.append("Собираю базу: день \(progress.days) из \(progress.needed).")
        }
        return parts.joined(separator: " ")
    }

    private static func title(for provider: ProviderID) -> String {
        switch provider {
        case .healthKit: return "Apple Health"
        case .nutrition: return "Питание"
        case .calendar: return "Календарь"
        case .tasks: return "Задачи"
        default: return provider.rawValue
        }
    }

    private static func text(for status: ProviderStatus) -> String {
        switch status {
        case .ready: return "Подключено"
        case .noData: return "Нет данных"
        case .indeterminate: return "Нет данных"
        case .unauthorized: return "Нет доступа"
        case .unavailable: return "Недоступно"
        case .timedOut: return "Не ответило"
        case .failed: return "Ошибка"
        }
    }
}
