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
            additionalProviders: [any ContextProvider] = []
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
        }
    }

    nonisolated struct Output: Sendable {
        let record: DayRecord
        let insight: SleepInsight
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

        let snapshot = await contextEngine.capture(
            request: request,
            snapshotID: DeterministicID.snapshotID(day: day, time: time, capturedAt: time.now),
            tasks: input.tasks,
            goals: input.goals,
            profile: input.profile,
            nutrition: input.nutrition,
            meals: input.meals,
            additionalProviders: input.additionalProviders
        )

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

        // A plan the user already accepted is revised, never rebuilt from
        // scratch: what they lived through is history, not a proposal.
        let accepted = input.existing?.plan.flatMap { $0.status == .accepted ? $0 : nil }
        var plan: DayPlan
        if let accepted {
            plan = decisionEngine.replan(accepted, snapshot: snapshot, state: state, calibration: input.calibration, time: time)
        } else {
            plan = decisionEngine.plan(
                snapshot: snapshot, state: state, calibration: input.calibration,
                time: time, planID: DeterministicID.planID(day: day, time: time)
            )
        }

        plan = await explained(plan, state: state, snapshot: snapshot, time: time)

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
            updatedAt: time.now
        )

        let series = DailySeriesBuilder().build(snapshot: snapshot, time: time)
        let insight = insightBuilder.build(history: input.history, today: series.summary, config: config, time: time)

        return Output(record: record, insight: insight, todaySummary: series.summary)
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
