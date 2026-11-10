//
//  PlanDayUseCase.swift
//  Linea
//
//  The morning of the wow-scenario, end to end: collect context from every
//  connector, work out how the user is doing, build the day, write the text
//  and prepare the nudges. One pure function, so the whole scenario is a test.
//
//  It takes data already loaded from repositories rather than loading it
//  itself: that keeps the core free of persistence and lets the store decide
//  what is worth re-reading.
//

import Foundation

nonisolated struct PlanDayUseCase: Sendable {
    let contextEngine: ContextEngine
    let stateEngine: StateEngine
    let decisionEngine: DecisionEngine
    let nudgeEngine: NudgeEngine
    let explainer: any Explainer
    let baselineCalculator: BaselineCalculator
    let insightBuilder: SleepInsightBuilder
    let config: EngineConfig

    init(
        contextEngine: ContextEngine,
        stateEngine: StateEngine = StateEngine(),
        decisionEngine: DecisionEngine,
        nudgeEngine: NudgeEngine,
        explainer: any Explainer,
        baselineCalculator: BaselineCalculator = BaselineCalculator(),
        insightBuilder: SleepInsightBuilder = SleepInsightBuilder(),
        config: EngineConfig = .default
    ) {
        self.contextEngine = contextEngine
        self.stateEngine = stateEngine
        self.decisionEngine = decisionEngine
        self.nudgeEngine = nudgeEngine
        self.explainer = explainer
        self.baselineCalculator = baselineCalculator
        self.insightBuilder = insightBuilder
        self.config = config
    }

    nonisolated struct Input: Sendable {
        let time: TimeContext
        let tasks: [LineaTask]
        let goals: [LineaGoal]
        let profile: UserProfile
        let nutrition: NutritionProfile?
        let meals: [MealLog]
        /// Daily aggregates for the days BEFORE today.
        let history: [DailyHealthSummary]
        let calibration: Calibration
        /// Yesterday's verdict, for hysteresis.
        let previousLoadAdvice: LoadAdvice?
        /// Today's record if the day was already planned.
        let existing: DayRecord?
        /// How many days of history the providers should fetch.
        let historyDays: Int
        /// Connectors built from data the caller just loaded (see ContextEngine).
        let additionalProviders: [any ContextProvider]
        /// Разрешено ли переписывать текст облачной моделью. Когда `false`,
        /// объяснитель вообще не вызывается — наружу не уходит ничего.
        let allowsRemoteExplanation: Bool

        init(
            time: TimeContext,
            tasks: [LineaTask],
            goals: [LineaGoal],
            profile: UserProfile = .default,
            nutrition: NutritionProfile? = nil,
            meals: [MealLog] = [],
            history: [DailyHealthSummary] = [],
            calibration: Calibration = .default,
            previousLoadAdvice: LoadAdvice? = nil,
            existing: DayRecord? = nil,
            historyDays: Int = 0,
            additionalProviders: [any ContextProvider] = [],
            allowsRemoteExplanation: Bool = true
        ) {
            self.time = time
            self.tasks = tasks
            self.goals = goals
            self.profile = profile
            self.nutrition = nutrition
            self.meals = meals
            self.history = history
            self.calibration = calibration
            self.previousLoadAdvice = previousLoadAdvice
            self.existing = existing
            self.historyDays = historyDays
            self.additionalProviders = additionalProviders
            self.allowsRemoteExplanation = allowsRemoteExplanation
        }
    }

    nonisolated struct Output: Sendable {
        let record: DayRecord
        let insight: SleepInsight
        let planImpact: PlanImpact
        /// Today's aggregates, so the caller can persist them for tomorrow's baseline.
        let todaySummary: DailyHealthSummary
    }

    func run(_ input: Input) async -> Output {
        let time = input.time
        let day = time.today
        let request = ContextRequest(
            day: time.dayInterval(containing: day),
            time: time,
            historyDays: input.historyDays
        )

        var snapshot = await contextEngine.capture(
            request: request,
            snapshotID: DeterministicID.snapshotID(day: day, time: time, capturedAt: time.now),
            tasks: input.tasks,
            goals: input.goals,
            profile: input.profile,
            nutrition: input.nutrition,
            meals: input.meals,
            additionalProviders: input.additionalProviders
        )

        // Начатое действие («Сейчас» → «Начать») держит своё время: план не
        // ставит на него другое, а пересборка обходит его.
        if let active = input.existing?.activeAction(tasks: input.tasks, at: time.now),
           let task = input.tasks.first(where: { $0.id == active.start.taskID }),
           !snapshot.commitments.contains(where: { $0.taskID == task.id }) {
            snapshot.commitments.append(Commitment(
                id: NextActionUseCase.commitmentID(for: task.id), title: task.title, start: active.at,
                end: active.at.addingTimeInterval(TimeInterval(active.start.minutes * 60)),
                kind: .task, source: .tasks, taskID: task.id
            ))
            snapshot.commitments.sort { lhs, rhs in
                lhs.start == rhs.start ? lhs.id < rhs.id : lhs.start < rhs.start
            }
        }

        let baselines = baselineCalculator.compute(history: input.history, config: config, time: time)
        let state = stateEngine.evaluate(
            StateInput(
                snapshot: snapshot,
                baselines: baselines,
                history: input.history,
                calibration: input.calibration,
                config: config,
                time: time,
                previousLoadAdvice: input.previousLoadAdvice
            )
        )

        // An accepted day keeps its history. A proposal keeps explicit placements.
        var previous = input.existing?.plan
        previous?.blocks.removeAll { block in
            guard block.kind == .focus, block.isPinned, let id = block.taskID else { return false }
            guard let task = snapshot.tasks.first(where: { $0.id == id }), task.cancelledAt == nil else { return true }
            if task.isDone { return false }
            guard task.startedAt == nil, !task.isFixed,
                  task.deferredUntil.map({ $0 <= time.now }) ?? true else { return true }
            guard let prior = input.existing?.snapshot?.tasks.first(where: { $0.id == id }) else { return false }
            return prior.date != task.date || prior.rescheduleMode != task.rescheduleMode
                || prior.estimatedMinutes != task.estimatedMinutes
        }
        if let blocks = previous?.blocks {
            let titles = Dictionary(uniqueKeysWithValues: snapshot.tasks.map { ($0.id, $0.title) })
            previous?.blocks = blocks.map { block in
                guard block.kind == .focus, block.isPinned, let title = block.taskID.flatMap({ titles[$0] })
                else { return block }
                var updated = block
                updated.title = title
                return updated
            }
        }

        func build(using state: UserState) -> DayPlan {
            if let previous, previous.status == .accepted || previous.blocks.contains(where: \.isPinned) {
                return decisionEngine.replan(previous, snapshot: snapshot, state: state, calibration: input.calibration, time: time)
            }
            return decisionEngine.plan(
                snapshot: snapshot, state: state, calibration: input.calibration,
                time: time, planID: DeterministicID.planID(day: day, time: time)
            )
        }

        var plan = build(using: state)
        let impact: PlanImpact
        if state.confidence > 0 {
            let baseline = build(using: .unknown(day: day, computedAt: time.now))
            impact = PlanImpact.compare(plan, with: baseline, after: time.now)
        } else {
            impact = .noData
        }

        if input.allowsRemoteExplanation {
            plan = await explained(plan, state: state, snapshot: snapshot, time: time)
        }

        let nudges = plan.status == .accepted
            ? nudgeEngine.nudges(
                NudgeContext(
                    plan: plan, snapshot: snapshot, state: state,
                    feedback: input.existing?.feedback ?? [],
                    existing: [], calibration: input.calibration, config: config, time: time
                )
            )
            : []

        let record = DayRecord(
            day: day,
            snapshot: snapshot,
            state: state,
            plan: plan,
            nudges: nudges,
            feedback: input.existing?.feedback ?? [],
            suggestions: input.existing?.suggestions ?? [],
            updatedAt: time.now
        )

        let series = DailySeriesBuilder().build(snapshot: snapshot, time: time)
        let insight = insightBuilder.build(history: input.history, today: series.summary, config: config, time: time)

        return Output(record: record, insight: insight, planImpact: impact, todaySummary: series.summary)
    }

    /// Fills the morning brief's `explanation` with the explainer's text. The
    /// rule-based `message` stays untouched, so an unavailable model degrades
    /// the wording, never the plan.
    private func explained(_ plan: DayPlan, state: UserState, snapshot: ContextSnapshot, time: TimeContext) async -> DayPlan {
        var plan = plan
        guard let index = plan.recommendations.firstIndex(where: { $0.kind == .dayBrief }) else { return plan }

        let request = ExplanationRequest(
            moment: .morning,
            facts: plan.recommendations[index].facts,
            taskTitles: plan.topTaskIDs.compactMap { id in snapshot.tasks.first { $0.id == id }?.title },
            localeIdentifier: time.locale.identifier,
            hour: time.timeOfDay(of: time.now).hour,
            userName: snapshot.profile.name,
            timeZoneIdentifier: time.timeZone.identifier
        )
        guard let explanation = try? await explainer.explain(request) else { return plan }
        plan.recommendations[index].explanation = explanation.body.isEmpty ? nil : explanation.body
        plan.explainerID = explanation.explainerID
        return plan
    }
}

/// Difference caused by the current state with the rest of the planning inputs held constant.
nonisolated enum PlanImpact: Equatable, Sendable {
    case noData
    case unchanged
    case workload(minutes: Int, difference: Int)
    case placement(title: String, start: Date)

    static func compare(_ actual: DayPlan, with baseline: DayPlan, after now: Date) -> Self {
        func upcoming(_ plan: DayPlan) -> [PlanBlock] {
            plan.blocks.filter { $0.kind == .focus && !$0.isPinned && $0.taskID != nil && $0.end > now }
        }
        let blocks = upcoming(actual)
        let reference = upcoming(baseline)
        let minutes = blocks.reduce(0) { $0 + $1.durationMinutes }
        let difference = minutes - reference.reduce(0) { $0 + $1.durationMinutes }
        if difference != 0 { return .workload(minutes: minutes, difference: difference) }

        let changed = blocks.first { block in
            guard let old = reference.first(where: { $0.taskID == block.taskID }) else { return true }
            return abs(old.start.timeIntervalSince(block.start)) >= 60
        }
        if let changed { return .placement(title: changed.title, start: changed.start) }
        return .unchanged
    }
}
