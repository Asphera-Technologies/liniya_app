//
//  GoalProgressEngine.swift
//  Linea
//
//  Прогресс цели — по её методу, а не одним процентом на всех (ADR-037):
//    • число — «18 из 50 пользователей», 36 %;
//    • этапы — ✓ Core loop · ● Onboarding · ○ QA; процент — только если у
//      каждого этапа есть вес, иначе «2 из 5 этапов»;
//    • этапы и числа — рядом, без общего процента;
//    • «отмечаю сам» — начало, в процессе, почти готово, готово;
//    • без процентов — стадия, последнее продвижение, действия за 30 дней.
//
//  Закрытые задачи цели прогресс не двигают: десять мелких задач — не 10 %
//  пути. Двигают закрытые этапы и обновлённые числа. Задачи идут в
//  «значимые действия» и «последнее продвижение».
//
//  Чистая функция от цели, её задач и времени: одинаково считает строка
//  цели в «Плане», карточка цели и движок приоритизации.
//

import Foundation

/// Прогресс цели так, как его можно честно показать.
nonisolated struct GoalProgress: Hashable, Sendable {
    /// Полоска под целью. Её нет, когда честно нарисовать нечего.
    nonisolated enum Bar: Hashable, Sendable {
        /// Доля 0…1: число или этапы с весами.
        case fraction(Double)
        /// Этапы без весов: закрытые отрезки из всех — не процент.
        case steps(done: Int, total: Int)
    }

    let method: GoalProgressMethod
    /// `progress_value`, 0…1: только когда его можно обоснованно посчитать —
    /// число с целью или этапы, у каждого из которых есть вес. Иначе nil, и
    /// процента нигде нет.
    let value: Double?
    /// Насколько цель близка к концу — только для важности её задач. Не
    /// показывается: у этапов без весов это просто доля закрытых.
    let completion: Double?
    let isCompleted: Bool
    /// Числа, которые видно: у «Числа» — главное, у «Этапов и чисел» — все.
    let metrics: [GoalMetric]
    let milestonesDone: Int
    let milestonesTotal: Int
    /// Следующий рубеж — первый незакрытый этап.
    let nextMilestone: GoalMilestone?
    /// Где цель, по словам человека (`manual`).
    let reportedState: GoalManualState?
    let stage: String?
    /// Последнее продвижение: закрытая задача цели, этап, число, стадия.
    let lastProgressAt: Date?
    /// Значимые действия за `GoalProgressEngine.recentDays` дней.
    let recentActions: Int

    var bar: Bar? {
        if isCompleted { return .fraction(1) }
        switch method {
        case .metric:
            return value.map(Bar.fraction)
        case .milestones:
            if let value { return .fraction(value) }
            return milestonesTotal > 0 ? .steps(done: milestonesDone, total: milestonesTotal) : nil
        case .hybrid:
            return milestonesTotal > 0 ? .steps(done: milestonesDone, total: milestonesTotal) : nil
        case .manual, .qualitative:
            return nil
        }
    }
}

nonisolated struct GoalProgressEngine: Sendable {
    /// Окно «значимых действий».
    static let recentDays = 30

    init() {}

    func progress(of goal: LineaGoal, tasks: [LineaTask], time: TimeContext) -> GoalProgress {
        let method = goal.progressMethod
        let shownMetrics: [GoalMetric]
        switch method {
        case .metric: shownMetrics = Array(goal.metrics.prefix(1))
        case .hybrid: shownMetrics = goal.metrics
        case .milestones, .manual, .qualitative: shownMetrics = []
        }

        // Значимые действия: закрытые задачи цели и продвижения из журнала.
        let closed = tasks
            .filter { $0.goalID == goal.id && $0.isDone && $0.cancelledAt == nil }
            .compactMap(\.completedAt)
        let moments = (closed + goal.progressLog.map(\.at)).filter { $0 <= time.now }
        let windowStart = time.adding(days: -Self.recentDays, to: time.now)

        return GoalProgress(
            method: method,
            value: Self.value(of: goal),
            completion: Self.completion(of: goal),
            isCompleted: goal.isCompleted,
            metrics: shownMetrics,
            milestonesDone: goal.milestones.filter(\.isDone).count,
            milestonesTotal: goal.milestones.count,
            nextMilestone: goal.nextMilestone,
            reportedState: method == .manual ? goal.reportedState : nil,
            stage: goal.stage,
            lastProgressAt: moments.max(),
            recentActions: moments.filter { $0 > windowStart }.count
        )
    }

    /// `progress_value`: доля, которую можно обоснованно посчитать, — или nil.
    static func value(of goal: LineaGoal) -> Double? {
        switch goal.progressMethod {
        case .metric: return goal.metrics.first?.fraction
        case .milestones: return weightedShare(goal.milestones)
        // У «этапов и чисел» общий процент необязателен — и не придумывается.
        case .hybrid, .manual, .qualitative: return nil
        }
    }

    /// Насколько цель близка к концу — для важности её задач (`TaskScorer`):
    /// почти достигнутая цель тянет чуть слабее. Без процентов — nil.
    static func completion(of goal: LineaGoal) -> Double? {
        if goal.isCompleted { return 1 }
        switch goal.progressMethod {
        case .metric:
            return goal.metrics.first?.fraction
        case .milestones:
            return weightedShare(goal.milestones) ?? countShare(goal.milestones)
        case .hybrid:
            var parts = goal.metrics.compactMap(\.fraction)
            if let share = weightedShare(goal.milestones) ?? countShare(goal.milestones) { parts.append(share) }
            return parts.isEmpty ? nil : parts.reduce(0, +) / Double(parts.count)
        case .manual:
            // Цель со слайдером — прежнее значение как было.
            return goal.manualState?.completion ?? goal.progress
        case .qualitative:
            return nil
        }
    }

    /// Доля этапов по весам — только если вес есть у каждого этапа: без
    /// уверенных весов точности нет, и Linea её не создаёт.
    static func weightedShare(_ milestones: [GoalMilestone]) -> Double? {
        guard !milestones.isEmpty else { return nil }
        var total = 0.0
        var done = 0.0
        for milestone in milestones {
            guard let weight = milestone.weight, weight > 0, weight.isFinite else { return nil }
            total += weight
            if milestone.isDone { done += weight }
        }
        return total > 0 ? done / total : nil
    }

    /// Доля закрытых этапов — для расчётов, не для экрана.
    static func countShare(_ milestones: [GoalMilestone]) -> Double? {
        guard !milestones.isEmpty else { return nil }
        return Double(milestones.filter(\.isDone).count) / Double(milestones.count)
    }
}
