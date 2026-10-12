//
//  GoalBalance.swift
//  Linea
//
//  Баланс между целями и текущей жизнью (ADR-039). Linea смотрит не только на
//  отдельные задачи, но и на состав дня: «5 обязательств, 3 бытовых дела, 0
//  шагов к целям». Если текущих дел много, шагов к важным целям сегодня нет,
//  а свободные полчаса ещё есть, — мягко спрашивает:
//
//      Сегодня много текущих дел.
//      Хочешь оставить небольшое окно для цели «Запустить Линия Beta»?
//      [Оставить 30 минут] [Не сегодня]
//
//  Ответ — один раз в день: после «Не сегодня» Linea в этот день больше не
//  спрашивает, после «Оставить 30 минут» шаг к цели сегодня уже есть.
//

import Foundation

/// Из чего состоит сегодняшний день: текущие дела и шаги к важным целям.
nonisolated struct DayComposition: Hashable, Sendable {
    /// Обязательства — задачи и встречи из календаря.
    var obligations = 0
    /// Быт и дела.
    var maintenance = 0
    /// Рутина, входящие, разовые — остальное текущее.
    var other = 0
    /// Задачи к важным целям.
    var goalSteps = 0

    var current: Int { obligations + maintenance + other }

    /// Сегодняшние задачи — в плане дня, назначенные на сегодня и закрытые
    /// сегодня, — и встречи из календаря. Отменённое не в счёт.
    static func of(
        tasks: [LineaTask],
        plan: DayPlan?,
        commitments: [Commitment],
        importantGoalIDs: Set<UUID>,
        time: TimeContext,
        classifier: TaskClassifier = TaskClassifier()
    ) -> DayComposition {
        let isTodayPlan = plan.map { time.isSameDay($0.day, time.now) } ?? false
        let planned = Set((isTodayPlan ? plan?.blocks ?? [] : []).compactMap(\.taskID))
        let today = tasks.filter { task in
            guard task.cancelledAt == nil else { return false }
            if planned.contains(task.id) { return true }
            if let date = task.date, time.isSameDay(date, time.now) { return true }
            if let completed = task.completedAt, time.isSameDay(completed, time.now) { return true }
            return false
        }
        var composition = DayComposition()
        for task in today {
            if let goalID = task.goalID, importantGoalIDs.contains(goalID) {
                composition.goalSteps += 1
                continue
            }
            switch classifier.kind(of: task) {
            case .obligation: composition.obligations += 1
            case .maintenance: composition.maintenance += 1
            case .goal, .routine, .incoming, .standalone: composition.other += 1
            }
        }
        // Встречи из календаря — тоже обязательства.
        composition.obligations += commitments.filter { commitment in
            commitment.source == .calendar && commitment.taskID == nil && time.isSameDay(commitment.start, time.now)
        }.count
        return composition
    }
}

nonisolated struct GoalBalance: Sendable {
    /// С какого числа текущих дел день «полон текущего».
    static let busyDay = 4
    /// Небольшое окно для цели.
    static let windowMinutes = 30

    init() {}

    /// Важные цели — активные, кроме низкой важности.
    static func importantGoals(_ goals: [LineaGoal]) -> [LineaGoal] {
        goals.filter { $0.isActive && !$0.isCompleted && $0.priority != .low }
    }

    /// Предложение окна для цели — или nil, если день и так в балансе, на
    /// окно нет времени или сегодня уже ответили.
    func offer(
        tasks: [LineaTask],
        goals: [LineaGoal],
        record: DayRecord?,
        profile: UserProfile,
        config: EngineConfig = .default,
        time: TimeContext
    ) -> GoalOffer? {
        guard let record, time.isSameDay(record.day, time.now) else { return nil }
        // Ответили сегодня — больше не спрашиваем.
        guard !record.goalOfferAnswers.contains(where: { $0.kind == .balance }) else { return nil }
        let important = Self.importantGoals(goals)
        guard let goal = NowReasoner.mainGoal(in: important) else { return nil }

        let composition = DayComposition.of(
            tasks: tasks, plan: record.plan, commitments: record.snapshot?.commitments ?? [],
            importantGoalIDs: Set(important.map(\.id)), time: time
        )
        guard composition.goalSteps == 0, composition.current >= Self.busyDay else { return nil }
        guard Self.hasWindow(minutes: Self.windowMinutes, record: record, profile: profile, config: config, time: time) else {
            return nil
        }
        return GoalOffer(
            kind: .balance,
            goalID: goal.id,
            goalTitle: goal.title,
            minutes: Self.windowMinutes,
            day: time.today,
            observation: "Сегодня много текущих дел.",
            question: "Хочешь оставить небольшое окно для цели \(RussianText.quoted(goal.title))?",
            detail: GoalSupportText.composition(composition),
            acceptTitle: "Оставить \(Self.windowMinutes) минут",
            declineTitle: "Не сегодня"
        )
    }

    /// Осталось ли сегодня свободное окно нужной длины: рабочий день минус
    /// план, встречи и еда, начиная с этой минуты.
    static func hasWindow(minutes: Int, record: DayRecord, profile: UserProfile, config: EngineConfig, time: TimeContext) -> Bool {
        let blocks = (record.plan?.blocks ?? []).map { block in
            Commitment(id: block.id, title: block.title, start: block.start, end: block.end, kind: .other, source: .tasks)
        }
        let busy = blocks + (record.snapshot?.commitments ?? [])
        let windows = FreeWindows.compute(day: time.today, now: time.now, profile: profile, commitments: busy,
                                          config: config, time: time)
        return windows.contains { $0.duration >= TimeInterval(minutes * 60) }
    }
}
