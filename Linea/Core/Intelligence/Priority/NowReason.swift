//
//  NowReason.swift
//  Linea
//
//  Почему «Сейчас» — именно это действие. У каждой рекомендации есть одна
//  причина, которую человек поймёт без техники: «Высокий приоритет, а срок —
//  сегодня вечером.», «До встречи 35 мин — на эту задачу как раз хватит.»,
//  «Это ближайший шаг по твоей главной цели.» Никаких баллов и
//  уверенностей: оценки движка (§16) решают, а причина их только называет.
//
//  Причин у выбора обычно несколько — называется самая понятная, по порядку:
//    1. важное не помещается в окно — сейчас то, на что окна хватит;
//    2. своё время задачи — сейчас;
//    3. срок прошёл или день задачи прошёл;
//    4. срок сегодня или завтра (вместе с высоким приоритетом, если он есть);
//    5. идёт её блок в принятом плане;
//    6. окно до следующего дела тесное, но задаче его хватает;
//    7. шаг к цели — главной или просто к цели;
//    8. высокий приоритет;
//    9. без неё не начать другие задачи;
//   10. её уже не раз откладывали;
//   11. сил сейчас хватает на сложное;
//   12. у неё нет даты, а свободное время есть;
//   13. она короткая;
//   14. иначе — самое важное из того, что можно сделать сейчас.
//

import Foundation

/// Главная причина действия «Сейчас». Числа — только отсюда: текст их не
/// считает, поэтому не может разойтись с тем, что видел движок.
nonisolated enum NowReason: Codable, Hashable, Sendable {
    /// Важное не помещается: «До встречи 20 мин — на это хватит, а
    /// «Подготовить стратегию» лучше после встречи.»
    case fitsBeforeLater(window: CommitmentKind?, windowTitle: String?, minutesLeft: Int, laterTitle: String)
    /// У задачи своё время, и оно сейчас.
    case startsAt(Date)
    /// Срок задачи уже прошёл.
    case overdue
    /// День задачи прошёл, а она не закрыта.
    case missedDay
    /// Срок сегодня или завтра; высокий приоритет добавляется к сроку.
    case deadline(Date, isTomorrow: Bool, isHighPriority: Bool)
    /// Сейчас идёт её блок принятого плана.
    case planned
    /// Окно до следующего дела тесное, но задаче его хватает.
    case fitsWindow(window: CommitmentKind?, windowTitle: String?, minutesLeft: Int)
    /// Шаг к главной цели — самой важной из активных.
    case mainGoalStep
    /// Шаг к цели.
    case goalStep(goalTitle: String)
    case highPriority
    /// Без неё не начать другие: одна — по названию, несколько — числом.
    case unblocks(count: Int, title: String?)
    /// Её откладывали уже столько раз.
    case deferred(times: Int)
    /// Сил сейчас хватает на сложное.
    case energyPeak
    /// У неё нет даты, а свободное время есть сейчас.
    case freeTime
    /// Короткая — закрывается сразу.
    case quick
    /// Ничего особенного — просто самое важное из уместного сейчас.
    case mostImportant
}

nonisolated struct NowReasoner: Sendable {
    /// Окно — причина, когда оно тесное: не длиннее часа или двух длительностей
    /// задачи, но и не длиннее двух часов — в такое помещается почти всё.
    static let tightWindowMinutes = 60
    static let maxTightWindowMinutes = 120
    /// Срок «скоро» — сегодня или завтра.
    static let soonDeadlineDays = 1
    /// С какого числа переносов это стоит сказать.
    static let deferralsWorthMentioning = 2
    /// Короткая задача — не дольше.
    static let quickMinutes = 15
    /// Сил хватает на сложное, если соответствие силам не ниже.
    static let energyPeakFit = 0.85

    init() {}

    /// Что известно о выборе: задача, её оценка, окно, «её лучше после» и
    /// почему она выбрана (план, выбор человека).
    nonisolated struct Choice: Sendable {
        let task: LineaTask
        let assessment: PriorityAssessment
        let window: PriorityWindow
        /// Важная задача, которой не хватает окна.
        let laterTitle: String?
        /// Задача стоит в идущем блоке принятого плана.
        let isPlanned: Bool
    }

    func reason(for choice: Choice, context: PriorityContext) -> NowReason {
        let task = choice.task
        let time = context.time
        let now = time.now
        let window = choice.window

        if let laterTitle = choice.laterTitle {
            return .fitsBeforeLater(window: window.until?.kind, windowTitle: window.until?.title,
                                    minutesLeft: window.minutes, laterTitle: laterTitle)
        }
        if let start = task.scheduledStart {
            return .startsAt(start)
        }
        if let deadline = task.deadline, deadline <= now {
            return .overdue
        }
        if task.deadline == nil, let date = task.date, time.startOfDay(date) < time.today {
            return .missedDay
        }
        if let deadline = task.deadline,
           time.startOfDay(deadline) <= time.adding(days: Self.soonDeadlineDays, to: time.today) {
            return .deadline(deadline, isTomorrow: !time.isSameDay(deadline, now), isHighPriority: task.priority == .important)
        }
        if choice.isPlanned {
            return .planned
        }
        if Self.isTight(window.minutes, for: choice.assessment.minutesNeeded) {
            return .fitsWindow(window: window.until?.kind, windowTitle: window.until?.title, minutesLeft: window.minutes)
        }
        if let goal = Self.goal(of: task, in: context.snapshot.goals) {
            return goal.id == Self.mainGoal(in: context.snapshot.goals)?.id ? .mainGoalStep : .goalStep(goalTitle: goal.title)
        }
        if task.priority == .important {
            return .highPriority
        }
        let waiting = context.dependencies.dependentIDs(of: task.id)
        if !waiting.isEmpty {
            let title = waiting.count == 1 ? context.snapshot.tasks.first { $0.id == waiting[0] }?.title : nil
            return .unblocks(count: waiting.count, title: title)
        }
        if task.deferralCount >= Self.deferralsWorthMentioning {
            return .deferred(times: task.deferralCount)
        }
        if task.cognitiveDemand == .deep, let energy = choice.assessment.actionFactors.energy, energy >= Self.energyPeakFit {
            return .energyPeak
        }
        if InboxReview.isInInbox(task) {
            return .freeTime
        }
        if choice.assessment.minutesNeeded <= Self.quickMinutes {
            return .quick
        }
        return .mostImportant
    }

    /// Задаче хватает окна, и оно тесное — значит, оно и есть причина.
    static func isTight(_ windowMinutes: Int, for neededMinutes: Int) -> Bool {
        neededMinutes <= windowMinutes
            && windowMinutes <= min(maxTightWindowMinutes, max(tightWindowMinutes, 2 * neededMinutes))
    }

    /// Активная цель задачи.
    static func goal(of task: LineaTask, in goals: [LineaGoal]) -> LineaGoal? {
        guard let goalID = task.goalID else { return nil }
        return goals.first { $0.id == goalID && $0.isActive && !$0.isCompleted }
    }

    /// Главная цель — самая важная из активных; при равной важности — с
    /// ближайшим сроком, потом — давняя.
    static func mainGoal(in goals: [LineaGoal]) -> LineaGoal? {
        goals.filter { $0.isActive && !$0.isCompleted }.min { lhs, rhs in
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
}
