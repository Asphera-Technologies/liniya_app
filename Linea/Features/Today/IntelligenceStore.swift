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
import OSLog

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
    private(set) var userProfile: UserProfile = .default
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    /// «Сейчас»: что разумнее всего делать в эту минуту — с готовым текстом.
    private(set) var nextAction: NextAction?
    /// Что человек выбрал в «Другое» — пока задача открыта.
    private var preferredTaskID: UUID?
    /// Сколько экранов «Сегодня» сейчас открыто: только тогда «Сейчас» видно
    /// и предложение записывается как показанное (`SuggestionLog`). Счётчик,
    /// а не флаг: новый экран может появиться раньше, чем уйдёт прежний.
    private var nowViewers = 0
    /// Действие с задачей сохраняется: день уже новый, а задачи ещё прежние —
    /// «Сейчас» по такой смеси не считается.
    private var executionsInFlight = 0

    // MARK: Dependencies

    private let planDayUseCase: PlanDayUseCase
    private let acceptPlanUseCase: AcceptPlanUseCase
    private let checkInUseCase: CheckInUseCase
    private let respondUseCase: RespondToNudgeUseCase
    private let ratingUseCase: RecordDayRatingUseCase
    private let nextActionUseCase: NextActionUseCase
    private let executionUseCase = TaskExecutionUseCase()
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
    private let calendarProvider: (@MainActor () -> any CalendarConnecting)?
    /// Свободный разговор с моделью. Nil, когда ключ не настроен.
    private let assistant: AssistantService?
    /// Память Linea: контекст для разговора и «запомни». Nil в превью.
    private let memory: MemoryStore?

    /// События календаря за уже показанные периоды, чтобы листание недель на
    /// экране «План» не перечитывало календарь каждый раз.
    private var calendarCache: [DateInterval: [Commitment]] = [:]

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
        calendarProvider: (@MainActor () -> any CalendarConnecting)? = nil,
        assistant: AssistantService? = nil,
        memory: MemoryStore? = nil
    ) {
        self.planDayUseCase = planDay
        self.acceptPlanUseCase = acceptPlan
        self.checkInUseCase = checkIn
        self.respondUseCase = respond
        self.ratingUseCase = recordRating
        self.nextActionUseCase = NextActionUseCase(config: config)
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
        self.assistant = assistant
        self.memory = memory
    }

    var time: TimeContext { timeProvider() }

    // MARK: - Refresh

    func refresh(reason: RefreshReason) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let time = self.time
        await memory?.loadIfNeeded()
        do {
            await planStore.load()
            let profile = try await profiles.load()
            userProfile = profile
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
                    additionalProviders: connectors(nutrition: nutrition, meals: meals, profile: profile),
                    allowsRemoteExplanation: profile.isCloudAssistantEnabled
                )
            )

            let record = mergingFeedback(into: output.record)
            apply(record)
            calendarCache.removeAll()
            sleepInsight = output.insight
            logSnapshot(record)
            try await records.save(record)
            await evaluateNudges(time: time)
            errorMessage = nil
        } catch {
            LineaLog.plan.error("Пересчёт дня не удался: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// Пока день пересчитывался, человек мог оценить день, сохранить итог,
    /// начать или закрыть задачу, а Linea — предложить новое: пересчёт
    /// начинал с прочитанной раньше записи и не должен это потерять.
    private func mergingFeedback(into record: DayRecord) -> DayRecord {
        guard let current = self.record, current.day == record.day else { return record }
        var merged = record
        merged.suggestions = SuggestionLog.merged(record.suggestions, with: current.suggestions)
        let known = Set(record.feedback.map(\.id))
        let newer = current.feedback.filter { !known.contains($0.id) }
        guard !newer.isEmpty else { return merged }
        merged.feedback = (record.feedback + newer).sorted { $0.at < $1.at }
        if merged.isReviewed { merged.nudges.removeAll { $0.kind == .eveningCheckIn } }
        return merged
    }

    private func connectors(nutrition: NutritionProfile?, meals: [MealLog], profile: UserProfile) -> [any ContextProvider] {
        var providers: [any ContextProvider] = [NutritionContextProvider(profile: nutrition, meals: meals)]
        if profile.isCalendarEnabled, let calendarProvider {
            providers.append(calendarProvider() as any ContextProvider)
        }
        return providers
    }

    /// Что именно получил движок: по этим строкам разбирается любая жалоба
    /// вида «приложение показывает не то».
    private func logSnapshot(_ record: DayRecord) {
        let statuses = (record.snapshot?.providerStatuses ?? [:])
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value)" }
            .joined(separator: ", ")
        LineaLog.context.notice("Источники: \(statuses.isEmpty ? "нет" : statuses, privacy: .public)")

        if let state = record.state {
            let components = state.components.map(\.kind.rawValue).joined(separator: ",")
            let energy = String(format: "%.2f", state.energy)
            let confidence = String(format: "%.2f", state.confidence)
            LineaLog.plan.notice("Состояние: энергия \(energy, privacy: .public), уверенность \(confidence, privacy: .public), совет \(state.loadAdvice.rawValue, privacy: .public), компоненты [\(components, privacy: .public)]")
        } else {
            LineaLog.plan.error("Состояние не посчиталось")
        }

        if let plan = record.plan {
            LineaLog.plan.notice("План: блоков \(plan.blocks.count, privacy: .public), приоритетов \(plan.topTaskIDs.count, privacy: .public), перенесено \(plan.deferredTaskIDs.count, privacy: .public)")
        }

        // Типы задач в интерфейсе не видны — журнал показывает, как Linea их поняла.
        let classifier = TaskClassifier()
        let kinds = Dictionary(grouping: (record.snapshot?.tasks ?? []).filter(\.isOpen)) { classifier.kind(of: $0).rawValue }
            .map { "\($0.key) \($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        LineaLog.plan.notice("Типы открытых задач: \(kinds.isEmpty ? "нет" : kinds, privacy: .public)")
    }

    /// Health history is read once a day: HealthKit is the source of truth,
    /// but four weeks of samples is not something to re-read on every tap.
    private func loadHistoryIfNeeded(time: TimeContext) async {
        if let loadedAt = historyLoadedAt, time.isSameDay(loadedAt, time.now), !historyCache.isEmpty { return }
        do {
            historyCache = try await history.dailySummaries(days: config.baselineWindowDays, before: time.today, time: time)
            historyLoadedAt = time.now
        } catch {
            // Без истории день всё равно планируется, просто осторожнее.
            LineaLog.health.error("История здоровья не прочиталась: \(error.localizedDescription, privacy: .public)")
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
            // «Закрываем сейчас» — человек берётся за задачу: она в работе,
            // как после «Начать». Задача сохраняется — день пересобирается.
            if case .finishNow(let taskID) = action,
               let task = planStore.tasks.first(where: { $0.id == taskID }), task.isOpen, task.startedAt == nil {
                await perform(.start, on: task)
            } else {
                await refresh(reason: .inputsChanged)
            }
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

    // MARK: - Итог дня

    /// Что итогу дня нужно знать о самом дне: запись, месяц истории для
    /// калибровки и текущую калибровку.
    func checkInContext(for day: Date) async -> (record: DayRecord?, history: [DayRecord], calibration: Calibration) {
        let time = self.time
        let record: DayRecord?
        if let current = self.record, time.isSameDay(current.day, day) {
            record = current
        } else {
            record = try? await records.record(for: day)
        }
        let history = (try? await records.records(since: time.adding(days: -30, to: time.today))) ?? []
        return (record, history, calibration)
    }

    /// Итог дня сохранён: в дне теперь план против факта и оценка, калибровка
    /// пересчитана, вечерний вопрос снят — и на экране, и в уведомлениях.
    func applyCheckIn(record: DayRecord, calibration: Calibration) async {
        let time = self.time
        if let current = self.record, time.isSameDay(current.day, record.day) {
            apply(record)
        }
        self.calibration = calibration
        do {
            try await records.save(record)
            try await calibrations.save(calibration)
        } catch {
            LineaLog.checkIn.error("Итог дня не записался в день: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
        if dueNudge?.kind == .eveningCheckIn { dueNudge = nil }
        if let scheduler, time.isSameDay(record.day, time.today), record.isPlanAccepted {
            await scheduler.sync(record.nudges, time: time)
        }
        await evaluateNudges(time: time)
    }

    /// Итог сегодняшнего дня, если он уже рассказан.
    var todayCheckIn: CheckInEntry? { memory?.todayEntry }

    /// Пора спросить «Как прошёл день?»: вечер, а итога ещё нет.
    var isCheckInDue: Bool {
        guard todayCheckIn == nil else { return false }
        let profile = record?.snapshot?.profile ?? userProfile
        return time.timeOfDay(of: time.now) >= profile.eveningCheckIn
    }

    /// Три кнопки оценки — только к принятому плану и пока день не оценён.
    var canRateDay: Bool {
        guard let record else { return false }
        return record.rating == nil && record.isPlanAccepted
    }

    // MARK: - Календарь на экране «План»

    /// События календаря за период. Пусто, если календарь не подключён.
    func calendarCommitments(in interval: DateInterval) async -> [Commitment] {
        guard userProfile.isCalendarEnabled, let calendarProvider else { return [] }
        if let cached = calendarCache[interval] { return cached }
        let events = (try? await calendarProvider().commitments(in: interval, time: time)) ?? []
        calendarCache[interval] = events
        return events
    }

    // MARK: - Nudges

    private func evaluateNudges(time: TimeContext) async {
        guard let record else { return }
        let output = checkInUseCase.run(record: record, tasks: planStore.tasks, calibration: calibration, time: time)
        dueNudge = output.due
        await updateNextAction(time: time)
        if let scheduler, plan?.status == .accepted {
            await scheduler.sync(output.scheduled, time: time)
        }
    }

    // MARK: - Сейчас

    /// Пока экран «Сегодня» открыт, «Сейчас» пересчитывается раз в минуту:
    /// началась встреча, закончилось окно — совет меняется сам.
    func keepNextActionFresh() async {
        nowViewers += 1
        defer { nowViewers -= 1 }
        while !Task.isCancelled {
            await updateNextAction(time: time)
            try? await Task.sleep(for: .seconds(60))
        }
    }

    /// «Сейчас» заново. Если экран открыт, показанное записывается в журнал
    /// предложений: та же задача — то же предложение, другая — прежнее
    /// закрывается без ответа.
    private func updateNextAction(time: TimeContext) async {
        guard executionsInFlight == 0 else { return }
        guard let record else {
            nextAction = nil
            return
        }
        if let preferred = preferredTaskID, !(planStore.tasks.first(where: { $0.id == preferred })?.isOpen ?? false) {
            preferredTaskID = nil
        }
        let action = nextActionUseCase.run(
            record: record, tasks: planStore.tasks, calibration: calibration, time: time, preferred: preferredTaskID
        )
        nextAction = action
        guard nowViewers > 0, time.isSameDay(record.day, time.now) else { return }
        let isAlternative = action?.taskID != nil && action?.taskID == preferredTaskID
        let tracked = SuggestionLog.tracking(action, newID: UUID(), isAlternative: isAlternative, in: record, at: time.now)
        guard tracked.suggestions != record.suggestions else { return }
        apply(tracked)
        // Без названий и причин: в них слова человека.
        if let open = SuggestionLog.open(in: tracked) {
            LineaLog.plan.notice("Предложено: из «Другое» \(open.isAlternative, privacy: .public), предложений за день \(tracked.suggestions.count, privacy: .public)")
        }
        await save(tracked, failure: "Предложение не записалось")
    }

    /// «Другое» → выбранная задача становится «сейчас». Прежнее предложение —
    /// «выбрано иное»: не отказ и не согласие.
    func chooseAlternative(_ option: NextAction.Option) async {
        let time = self.time
        var answered: DayRecord?
        if let record, time.isSameDay(record.day, time.now), let current = nextAction?.taskID, nextAction?.isStarted == false {
            let result = SuggestionLog.responding(.otherChosen, to: current, in: record, at: time.now)
            if result.suggestionID != nil {
                apply(result.record)
                answered = result.record
            }
        }
        preferredTaskID = option.taskID
        if let answered { await save(answered, failure: "Выбор в «Другое» не записался") }
        await updateNextAction(time: time)
    }

    /// «Начать» на «Сейчас».
    func startAction() async {
        guard let action = nextAction, let option = action.option, !action.isStarted,
              let task = planStore.tasks.first(where: { $0.id == option.taskID }) else { return }
        await perform(.start, on: task, plannedMinutes: option.minutes)
    }

    /// «Завершить» на начатом действии — задача закрыта, «сейчас» — следующее.
    func finishAction() async {
        guard let action = nextAction, let option = action.option,
              let task = planStore.tasks.first(where: { $0.id == option.taskID }) else { return }
        await perform(.finish, on: task, plannedMinutes: option.minutes)
    }

    /// «Не сейчас» на «Сейчас»: предложенное или начатое откладывается на
    /// полтора часа, Linea предлагает другое.
    func notNowAction() async {
        guard let action = nextAction, let option = action.option,
              let task = planStore.tasks.first(where: { $0.id == option.taskID }) else { return }
        await perform(.notNow, on: task, plannedMinutes: option.minutes)
    }

    // MARK: - Выполнение задач

    /// «Начать», «Завершить» («Готово»), «Не сейчас», «Удалить», «Вернуть» —
    /// откуда бы человек их ни нажал: «Сейчас», строка списка, карточка.
    /// Задача меняется по правилу ядра (`TaskExecutionUseCase`), в день
    /// пишется отклик и ответ на предложение Linea, план пересобирается.
    /// `plannedMinutes` — сколько отводила Linea; по умолчанию — по плану.
    func perform(_ action: TaskExecutionUseCase.Action, on task: LineaTask, plannedMinutes: Int? = nil) async {
        let time = self.time
        // Свежая версия: карточку могли открыть до того, как задачу начали.
        let current = planStore.tasks.first { $0.id == task.id } ?? task
        // Запись прошлого дня не трогаем: в неё сегодняшнее не пишется.
        let day = record.flatMap { time.isSameDay($0.day, time.now) ? $0 : nil }
        let minutes = plannedMinutes ?? PlanDuration.minutes(for: current, calibration: calibration)
        guard let output = executionUseCase.run(
            action, task: current, others: planStore.tasks, record: day, plannedMinutes: minutes, at: time.now
        ) else {
            LineaLog.plan.error("Задача: переход \(action.rawValue, privacy: .public) невозможен")
            return
        }
        executionsInFlight += 1
        // День — раньше задач: пересборка после сохранения задач читает его.
        if let updated = output.record {
            apply(updated)
            await save(updated, failure: "Действие с задачей не записалось в день")
        }
        if action == .start || current.id == preferredTaskID { preferredTaskID = nil }
        let suggestionID = output.task.suggestionID
        let actual = output.task.actualMinutes.map { "\($0)" } ?? "нет"
        LineaLog.plan.notice("Задача: \(action.rawValue, privacy: .public), предложение Linea \(suggestionID != nil, privacy: .public), заняло \(actual, privacy: .public) мин, снято с работы \(output.paused.count, privacy: .public)")
        await planStore.saveTasks([output.task] + output.paused)
        executionsInFlight -= 1
        // Пересчёт мог не начаться, если шёл другой: «Сейчас» — по свежим задачам.
        await updateNextAction(time: self.time)
    }

    /// Галочка и свайп «Готово» / «Вернуть».
    func toggleDone(_ task: LineaTask) async {
        await perform(task.isDone ? .reopen : .finish, on: task)
    }

    private func save(_ record: DayRecord, failure: String) async {
        do {
            try await records.save(record)
        } catch {
            LineaLog.plan.error("\(failure, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
        case .open, .tellDay:
            // Экран итога дня открывает AppDelegate через AppState.
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

    /// Когда сегодняшний план поставил задачу. Для «Без даты» это значит,
    /// что Linea сама нашла ей время.
    func plannedStart(for taskID: UUID) -> Date? {
        let now = time.now
        guard let plan, time.isSameDay(plan.day, now) else { return nil }
        return plan.blocks.first { $0.taskID == taskID && $0.kind == .focus && $0.end > now }?.start
    }

    var topTask: LineaTask? {
        guard let id = plan?.topTaskIDs.first else { return nil }
        return planStore.tasks.first { $0.id == id }
    }

    /// What is still ahead: everything that has not ended yet, plus tasks that
    /// were due earlier and are still open. A meal that already happened is not
    /// news; an unfinished task is. A task the person removed («Удалить») is
    /// gone from the day too, even before the plan is rebuilt.
    var visibleBlocks: [PlanBlock] {
        let now = time.now
        let taskIDs = Set(planStore.tasks.map(\.id))
        return (plan?.blocks ?? [])
            .filter { block in
                if let taskID = block.taskID, !taskIDs.contains(taskID) { return false }
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

    /// Может ли экран Linea AI разговаривать свободно.
    var isAssistantAvailable: Bool {
        assistant != nil && userProfile.isCloudAssistantEnabled
    }

    /// Свободный вопрос уходит модели вместе с уже посчитанным контекстом.
    /// Готовые подсказки по-прежнему отвечают мгновенно и без сети.
    func ask(_ question: String) async -> String {
        // «Запомни, что…» работает и без модели: память — на телефоне.
        if let command = MemoryCommand.command(in: question), let memory {
            let facts = await memory.remember([command], source: .chat)
            guard !facts.isEmpty else { return "Не получилось сохранить — попробуй сформулировать иначе." }
            return "Сохранено в памяти: «\(command.text)». Посмотреть или удалить — «Профиль» → «Память»."
        }
        if let quick = quickAnswer(to: question) { return quick }
        guard let assistant, userProfile.isCloudAssistantEnabled else {
            return AISettings.isConfigured
                ? "Свободный разговор выключен. Включить: «Профиль» → «Linea AI»."
                : "Пока отвечаю только про план, сон и еду: ключ доступа к модели не настроен."
        }
        do {
            // Память — в пределах бюджета: сколько бы дней ни прошло, в запрос
            // уходит не больше нескольких сотен токенов выжимок и фактов.
            let remembered = memory?.context(for: question)
            if let remembered, !remembered.isEmpty {
                LineaLog.ai.notice("Память в запросе: фактов \(remembered.factCount, privacy: .public), дней \(remembered.dayCount, privacy: .public), ≈\(remembered.estimatedTokens, privacy: .public) токенов")
            }
            return try await assistant.answer(
                to: question,
                context: AssistantService.Context(
                    state: state,
                    plan: plan,
                    sleep: sleepInsight,
                    nutrition: record?.snapshot?.nutrition,
                    taskTitles: planStore.tasks.filter { !$0.isDone }.map(\.title),
                    memory: remembered?.text,
                    time: time
                )
            )
        } catch {
            LineaLog.ai.error("Модель не ответила: \(error.localizedDescription, privacy: .public)")
            return "Не дозвонился до модели: \(error.localizedDescription)"
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

    /// Подсказки, на которые есть точный ответ без сети.
    private func quickAnswer(to question: String) -> String? {
        let lowercased = question.lowercased()
        if lowercased.contains("сон") || lowercased.contains("спал") { return sleepAnswer }
        if lowercased.contains("план на сегодня") { return brief?.message }
        return nil
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
