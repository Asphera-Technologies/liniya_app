//
//  WeeklyReview.swift
//  Linea
//
//  Мягкий обзор прогресса за неделю (ADR-044):
//
//      На этой неделе
//      Linea Beta        3 продвижения
//      Asphera Sales     2 продвижения
//      Большая часть недели ушла на текущие обязательства. По «Linea Beta»
//      получилось продвинуться трижды.
//
//  Продвижение — то же, что значимое действие цели (`GoalProgressEngine`):
//  закрытая задача цели, закрытый этап, число ближе к цели, следующая
//  стадия, «почти готово»; у общей цели — и своя часть. Наблюдение — одно,
//  о том, на что ушла неделя: текущие дела или цели, по закрытым задачам
//  (сколько заняли на самом деле или по оценке) и встречам из календаря.
//  Без оценки человека: ни «молодец», ни «мало», ни «отстаёшь» — только что
//  было.
//

import Foundation

nonisolated struct WeeklyReview: Hashable, Sendable {
    nonisolated struct GoalLine: Hashable, Sendable, Identifiable {
        let goalID: UUID
        let title: String
        let advances: Int
        /// «3 продвижения», «пока без продвижений».
        let summary: String

        var id: UUID { goalID }
    }

    /// «На этой неделе», «На неделе 5–11 окт».
    let title: String
    let goals: [GoalLine]
    /// Одно наблюдение о неделе; nil — сказать пока нечего: данных мало.
    let observation: String?
}

nonisolated struct WeeklyReviewBuilder: Sendable {
    /// Наблюдение — когда за неделю закрыто хотя бы столько задач…
    static let minimumTasks = 3
    /// …или набралось столько минут дел и встреч.
    static let minimumMinutes = 120
    /// «Большая часть недели» — не меньше такой доли.
    static let majorityShare = 0.6

    private let classifier = TaskClassifier()

    init() {}

    /// Обзор недели `week`; nil — неделя ещё не началась или целей нет.
    func review(
        week: DateInterval,
        goals: [LineaGoal],
        tasks: [LineaTask],
        meetings: [Commitment] = [],
        time: TimeContext
    ) -> WeeklyReview? {
        guard week.start <= time.now else { return nil }
        let isCurrent = week.contains(time.now)
        let upTo = min(week.end, time.now)
        let inWeek: (Date) -> Bool = { $0 >= week.start && $0 < upTo }

        let closed = tasks.filter { task in
            task.isDone && task.cancelledAt == nil && (task.completedAt.map(inWeek) ?? false)
        }

        // Продвижения по каждой цели — закрытые задачи и движение самой цели.
        let advances = Dictionary(uniqueKeysWithValues: goals.map { goal in
            let done = closed.filter { $0.goalID == goal.id }.count
            let moves = goal.progressLog.filter { inWeek($0.at) }.count
            return (goal.id, done + moves)
        })
        let shown = goals
            .filter { ($0.isActive && !$0.isCompleted) || (advances[$0.id] ?? 0) > 0 }
            .sorted { lhs, rhs in
                let left = advances[lhs.id] ?? 0
                let right = advances[rhs.id] ?? 0
                if left != right { return left > right }
                return Self.isMoreImportant(lhs, than: rhs)
            }
        guard !shown.isEmpty else { return nil }

        let lines = shown.map { goal in
            let count = advances[goal.id] ?? 0
            return WeeklyReview.GoalLine(goalID: goal.id, title: goal.title, advances: count,
                                         summary: Self.summary(count, isCurrent: isCurrent))
        }
        return WeeklyReview(
            title: Self.title(week: week, isCurrent: isCurrent, time: time),
            goals: lines,
            observation: observation(closed: closed, meetings: meetings, top: lines.first,
                                     inWeek: inWeek, upTo: upTo, isCurrent: isCurrent)
        )
    }

    // MARK: Наблюдение

    /// На что ушла неделя: текущие дела (обязательства, быт, остальное) и
    /// встречи — или шаги к целям; и где получилось продвинуться больше всего.
    private func observation(
        closed: [LineaTask],
        meetings: [Commitment],
        top: WeeklyReview.GoalLine?,
        inWeek: (Date) -> Bool,
        upTo: Date,
        isCurrent: Bool
    ) -> String? {
        var obligations = 0
        var current = 0
        var steps = 0
        for task in closed {
            let minutes = task.actualMinutes ?? TaskEstimate.minutes(for: task, classifier: classifier)
            if task.goalID != nil {
                steps += minutes
            } else {
                current += minutes
                if classifier.kind(of: task) == .obligation { obligations += minutes }
            }
        }
        // Встречи из календаря — тоже обязательства.
        for meeting in meetings where meeting.source == .calendar && meeting.taskID == nil && inWeek(meeting.start) {
            let minutes = Int(min(meeting.end, upTo).timeIntervalSince(meeting.start) / 60)
            current += max(0, minutes)
            obligations += max(0, minutes)
        }
        let total = current + steps
        guard closed.count >= Self.minimumTasks || total >= Self.minimumMinutes, total > 0 else { return nil }

        let share = Double(current) / Double(total)
        let first: String
        if share >= Self.majorityShare {
            first = "Большая часть недели ушла на текущие \(obligations * 2 >= current ? "обязательства" : "дела")."
        } else if share <= 1 - Self.majorityShare {
            first = "Большая часть недели ушла на цели."
        } else {
            first = "Неделя поделилась между текущими делами и целями."
        }
        let second: String
        if let top, top.advances > 0 {
            second = "По \(RussianText.quoted(top.title)) получилось продвинуться \(Self.times(top.advances))."
        } else {
            second = isCurrent ? "Шагов к целям на этой неделе пока не было." : "Шагов к целям за неделю не было."
        }
        return "\(first) \(second)"
    }

    // MARK: Тексты

    /// «3 продвижения», «1 продвижение»; ноль — «пока без продвижений».
    static func summary(_ count: Int, isCurrent: Bool) -> String {
        guard count > 0 else { return isCurrent ? "пока без продвижений" : "без продвижений" }
        return "\(count) " + RussianText.plural(count, "продвижение", "продвижения", "продвижений")
    }

    /// «один раз», «дважды», «трижды», «4 раза», «5 раз».
    static func times(_ count: Int) -> String {
        switch count {
        case 1: return "один раз"
        case 2: return "дважды"
        case 3: return "трижды"
        default: return "\(count) " + RussianText.plural(count, "раз", "раза", "раз")
        }
    }

    /// «На этой неделе»; прошедшая — «На неделе 5–11 окт», через месяц —
    /// «На неделе 28 сен – 4 окт».
    static func title(week: DateInterval, isCurrent: Bool, time: TimeContext) -> String {
        guard !isCurrent else { return "На этой неделе" }
        let last = week.end.addingTimeInterval(-1)
        let from = time.calendar.dateComponents([.day, .month], from: week.start)
        let to = time.calendar.dateComponents([.day, .month], from: last)
        let month: (Int?) -> String = { RussianText.monthsShort[(($0 ?? 1) - 1 + 12) % 12] }
        if from.month == to.month {
            return "На неделе \(from.day ?? 1)–\(to.day ?? 1) \(month(to.month))"
        }
        return "На неделе \(from.day ?? 1) \(month(from.month)) – \(to.day ?? 1) \(month(to.month))"
    }

    /// Порядок целей при равных продвижениях — как у главной цели: важнее,
    /// потом с ближним сроком, потом давняя.
    private static func isMoreImportant(_ lhs: LineaGoal, than rhs: LineaGoal) -> Bool {
        if lhs.priority.score != rhs.priority.score { return lhs.priority.score > rhs.priority.score }
        switch (lhs.endDate, rhs.endDate) {
        case let (left?, right?) where left != right: return left < right
        case (.some, nil): return true
        case (nil, .some): return false
        default: break
        }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
