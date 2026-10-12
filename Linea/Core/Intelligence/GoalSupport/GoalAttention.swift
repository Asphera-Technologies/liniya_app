//
//  GoalAttention.swift
//  Linea
//
//  Вернуть внимание к цели (ADR-040). Важная цель давно не двигалась —
//  Linea не пишет «ты отстаёшь», а спрашивает:
//
//      По цели «Linea Beta» не было действий четыре дня.
//      Хочешь найти для неё небольшое окно завтра?
//      [Да] [Пока нет]
//
//  «Да» — завтра Linea найдёт для цели 30 минут. «Пока нет» — Linea
//  отступает: неделю об этой цели не напоминает. Не больше одного такого
//  вопроса в день.
//

import Foundation

nonisolated struct GoalAttention: Sendable {
    /// Сколько дней без действий — «давно».
    static let idleDays = 4
    /// «Пока нет» — на сколько дней Linea отступает.
    static let snoozeDays = 7
    static let windowMinutes = 30

    init() {}

    func offer(goals: [LineaGoal], tasks: [LineaTask], record: DayRecord?, time: TimeContext) -> GoalOffer? {
        // Один такой вопрос в день — и после ответа больше не спрашиваем.
        if let record, time.isSameDay(record.day, time.now),
           record.goalOfferAnswers.contains(where: { $0.kind == .returnAttention }) {
            return nil
        }
        let tomorrow = time.adding(days: 1, to: time.today)
        let candidates = GoalBalance.importantGoals(goals).compactMap { goal -> (goal: LineaGoal, idle: Int)? in
            if let snoozed = goal.attentionSnoozedUntil, snoozed > time.now { return nil }
            // У цели уже есть окно — сегодня, завтра или идущая задача.
            let linked = tasks.filter { $0.goalID == goal.id && $0.isOpen }
            let hasWindow = linked.contains { task in
                if task.startedAt != nil { return true }
                return [task.date, task.scheduledStart, task.deadline].compactMap { $0 }.contains { day in
                    time.isSameDay(day, time.now) || time.isSameDay(day, tomorrow)
                }
            }
            guard !hasWindow else { return nil }
            let idle = time.days(from: GoalProgressEngine.lastAction(of: goal, tasks: tasks, time: time), to: time.now)
            // Человек недавно пересматривал цель — значит, думал о ней: не торопим.
            let reviewed = goal.lastReviewedAt.map { time.days(from: $0, to: time.now) } ?? idle
            guard idle >= Self.idleDays, reviewed >= Self.idleDays else { return nil }
            return (goal, idle)
        }
        // Важнее — первой; при равной важности — та, что дольше без движения.
        guard let chosen = candidates.min(by: { lhs, rhs in
            if lhs.goal.priority.score != rhs.goal.priority.score { return lhs.goal.priority.score > rhs.goal.priority.score }
            if lhs.idle != rhs.idle { return lhs.idle > rhs.idle }
            return lhs.goal.createdAt < rhs.goal.createdAt
        }) else { return nil }

        return GoalOffer(
            kind: .returnAttention,
            goalID: chosen.goal.id,
            goalTitle: chosen.goal.title,
            minutes: Self.windowMinutes,
            day: tomorrow,
            observation: "По цели \(RussianText.quoted(chosen.goal.title)) не было действий \(GoalSupportText.idle(days: chosen.idle)).",
            question: "Хочешь найти для неё небольшое окно завтра?",
            detail: nil,
            acceptTitle: "Да",
            declineTitle: "Пока нет"
        )
    }

    /// «Пока нет»: до этого момента Linea о цели не напоминает.
    static func snoozed(until time: TimeContext) -> Date {
        time.adding(days: snoozeDays, to: time.now)
    }
}
