//
//  TaskScorer.swift
//  Linea
//
//  Why a task deserves the next free slot, as five independent 0…1 factors
//  (Docs/intelligence.md §7). The breakdown is stored in the plan block so the
//  UI can explain the order and the Feedback Engine can look at it later; the
//  weights themselves are product constants and are never learned.
//
//  A factor that has nothing to say is EXCLUDED, not defaulted to 0.5: with no
//  health data `energyFit` would otherwise silently pull every task towards
//  the middle. Excluding it redistributes its weight over the rest instead.
//

import Foundation

/// How long the planner reserves for a task: the user's estimate stretched by
/// the calibrated multiplier (people underestimate their own tasks).
nonisolated enum PlanDuration {
    static func minutes(for task: LineaTask, calibration: Calibration) -> Int {
        let raw = Double(task.effectiveEstimatedMinutes) * calibration.estimateMultiplier
        return max(5, Int(raw.rounded()))
    }
}

nonisolated struct TaskScorer: Sendable {
    /// Urgency of a task nothing is pressing: present, but never competitive.
    static let neutralUrgency = 0.15
    /// Slack (hours) at which urgency has decayed by e — a day and a half of work.
    static let urgencyDecayHours = 36.0

    init() {}

    func score(
        task: LineaTask,
        at slotStart: Date,
        windowMinutes: Int,
        snapshot: ContextSnapshot,
        state: UserState,
        calibration: Calibration = .default,
        config: EngineConfig = .default,
        time: TimeContext
    ) -> ScoreBreakdown {
        let planned = PlanDuration.minutes(for: task, calibration: calibration)
        let urgencyValue = urgency(task: task, plannedMinutes: planned, at: slotStart, profile: snapshot.profile, time: time)
        let importanceValue = importance(task: task, snapshot: snapshot)
        let alignmentValue = goalAlignment(task: task, snapshot: snapshot, at: slotStart, time: time)
        let energyValue = energyFit(task: task, at: slotStart, state: state, config: config, time: time)
        let durationValue = durationFit(plannedMinutes: planned, windowMinutes: windowMinutes, config: config)

        var weighted = 0.0
        var weights = 0.0
        func add(_ value: Double, _ weight: Double) {
            weighted += value * weight
            weights += weight
        }
        add(urgencyValue, config.weightUrgency)
        add(importanceValue, config.weightImportance)
        add(alignmentValue, config.weightGoalAlignment)
        if let energyValue { add(energyValue, config.weightEnergyFit) }
        add(durationValue, config.weightDurationFit)

        return ScoreBreakdown(
            urgency: urgencyValue,
            importance: importanceValue,
            goalAlignment: alignmentValue,
            energyFit: energyValue,
            durationFit: durationValue,
            total: weights > 0 ? StateMath.clamp(weighted / weights) : 0
        )
    }

    // MARK: - Factors

    /// A task the user pinned to a clock time already owns its slot, so nothing
    /// about it can slip: it stays at the neutral floor instead of climbing as
    /// the day runs out — otherwise a 17:00 workout would out-rank real work.
    func urgency(task: LineaTask, plannedMinutes: Int, at slotStart: Date, profile: UserProfile, time: TimeContext) -> Double {
        guard !task.isFixed else { return Self.neutralUrgency }
        guard let moment = deadlineMoment(for: task, profile: profile, time: time) else { return Self.neutralUrgency }
        let hoursLeft = moment.timeIntervalSince(slotStart) / 3600
        let slack = hoursLeft - Double(plannedMinutes) / 60
        guard slack > 0 else { return 1 }
        return StateMath.clamp(exp(-slack / Self.urgencyDecayHours))
    }

    /// Explicit deadline, else the end of the workday on the day the task is
    /// planned for. A task with neither is not urgent by construction.
    func deadlineMoment(for task: LineaTask, profile: UserProfile, time: TimeContext) -> Date? {
        if let deadline = task.deadline { return deadline }
        guard let day = task.date else { return nil }
        return time.date(on: day, at: profile.workdayEnd)
    }

    func importance(task: LineaTask, snapshot: ContextSnapshot) -> Double {
        var value = task.priority.score
        if let goal = activeGoal(of: task, in: snapshot), goal.horizon == .week {
            value += 0.2
        }
        return StateMath.clamp(value)
    }

    func goalAlignment(task: LineaTask, snapshot: ContextSnapshot, at slotStart: Date, time: TimeContext) -> Double {
        guard let goalID = task.goalID else { return 0 }
        guard let goal = snapshot.goals.first(where: { $0.id == goalID }) else { return 0 }
        guard goal.isActive, !goal.isCompleted else { return 0.2 }
        let daysLeft = max(0, time.days(from: slotStart, to: goal.targetDate(calendar: time.calendar)))
        let horizonBonus = goal.horizon == .week ? 0.3 : 0.15
        let base = 0.6 + horizonBonus + 0.1 * exp(-Double(daysLeft) / 7)
        return StateMath.clamp(base * (1 - 0.3 * goal.progress))
    }

    /// `nil` when the day's energy is not trustworthy enough to judge fit.
    func energyFit(task: LineaTask, at slotStart: Date, state: UserState, config: EngineConfig, time: TimeContext) -> Double? {
        guard state.confidence >= config.minimumEnergyConfidence else { return nil }
        let capacity = Circadian.capacity(energy: state.energy, at: slotStart, time: time)
        let gap = task.cognitiveDemand.score - capacity
        if gap <= 0 {
            // Spending a peak on something trivial is a mild waste, not a sin.
            return StateMath.clamp(1 - 0.5 * (-gap))
        }
        return StateMath.clamp(1 - 1.5 * gap)
    }

    func durationFit(plannedMinutes: Int, windowMinutes: Int, config: EngineConfig) -> Double {
        guard windowMinutes >= config.minimumBlockMinutes else { return 0 }
        guard plannedMinutes > windowMinutes else { return 1 }
        return StateMath.clamp(0.6 * Double(windowMinutes) / Double(plannedMinutes))
    }

    // MARK: - Helpers

    private func activeGoal(of task: LineaTask, in snapshot: ContextSnapshot) -> LineaGoal? {
        guard let goalID = task.goalID else { return nil }
        guard let goal = snapshot.goals.first(where: { $0.id == goalID }) else { return nil }
        return goal.isActive && !goal.isCompleted ? goal : nil
    }
}
