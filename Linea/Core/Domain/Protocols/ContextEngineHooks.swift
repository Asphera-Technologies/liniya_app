//
//  ContextEngineHooks.swift
//  Linea
//
//  Extension points of the intelligence core. A connector may register:
//    • a `ContextProvider`  — new signals (see ContextProvider.swift);
//    • a `StateAnalyzer`    — a new component of the user's state (e.g. fuel);
//    • a `PlanRule`         — a post-processing rule on the day plan;
//    • a `NudgeRule`        — a new kind of moment-bound prompt.
//  Registration happens only in the app's composition root. The engines
//  themselves never reference a concrete connector.
//

import Foundation

// MARK: - State

/// Input for state analyzers: the snapshot, personal baselines and time.
nonisolated struct StateInput: Sendable {
    let snapshot: ContextSnapshot
    let baselines: BaselineSet?
    /// Daily summaries BEFORE today, oldest first (today comes from the snapshot).
    let history: [DailyHealthSummary]
    let calibration: Calibration
    let config: EngineConfig
    let time: TimeContext
    /// Yesterday's advice, for hysteresis.
    let previousLoadAdvice: LoadAdvice?

    init(
        snapshot: ContextSnapshot,
        baselines: BaselineSet?,
        history: [DailyHealthSummary],
        calibration: Calibration = .default,
        config: EngineConfig = .default,
        time: TimeContext,
        previousLoadAdvice: LoadAdvice? = nil
    ) {
        self.snapshot = snapshot
        self.baselines = baselines
        self.history = history
        self.calibration = calibration
        self.config = config
        self.time = time
        self.previousLoadAdvice = previousLoadAdvice
    }
}

/// Produces one component of `UserState` (or nil when it has nothing to say).
nonisolated protocol StateAnalyzer: Sendable {
    var kind: StateComponentKind { get }
    func analyze(_ input: StateInput) -> StateComponent?
}

// MARK: - Planning

/// Everything a planning rule may look at.
nonisolated struct PlanningContext: Sendable {
    let snapshot: ContextSnapshot
    let state: UserState
    let calibration: Calibration
    let config: EngineConfig
    let time: TimeContext
    /// Free windows the planner used (after commitments), for rules that add blocks.
    let freeWindows: [DateInterval]
}

/// Adjusts a drafted plan and/or adds recommendations. Applied in order after
/// the greedy placement; must be deterministic.
nonisolated protocol PlanRule: Sendable {
    var id: String { get }
    func apply(to plan: inout DayPlan, context: PlanningContext) -> [Recommendation]
}

// MARK: - Nudges

nonisolated struct NudgeContext: Sendable {
    let plan: DayPlan
    let snapshot: ContextSnapshot
    let state: UserState
    /// Feedback recorded today (for cooldowns / dedup).
    let feedback: [UserFeedback]
    /// Nudges already scheduled or delivered today.
    let existing: [Nudge]
    let calibration: Calibration
    let config: EngineConfig
    let time: TimeContext
}

/// Computes nudges for the rest of the day from an ACCEPTED plan.
nonisolated protocol NudgeRule: Sendable {
    var id: String { get }
    func nudges(_ context: NudgeContext) -> [Nudge]
}
