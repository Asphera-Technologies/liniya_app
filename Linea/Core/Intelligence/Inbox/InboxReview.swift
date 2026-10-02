//
//  InboxReview.swift
//  Linea
//
//  «Без даты» — входящие. Задача может жить вообще без дня и срока: человек
//  написал «Посмотреть новые AI-модели», нажал «Добавить» — и всё, Linea не
//  спрашивает «Когда?». Дальше два пути. Linea сама ставит пару таких задач в
//  свободное время дня (`PriorityEngine.inboxPicks`), а когда их накопится,
//  предлагает быстро разобрать: по одной задаче, с подсказкой, куда её.
//
//  Чистые функции: что лежит во входящих, когда предлагать разбор, что
//  подсказать по задаче и что станет с задачей после выбора. Тексты — здесь
//  же, экран только показывает их.
//

import Foundation

nonisolated struct InboxReview: Sendable {
    /// Столько неразобранных задач — повод предложить разбор.
    static let offerCount = 3
    /// Неразобранная задача лежит столько дней — тоже повод.
    static let staleDays = 3

    /// Куда человек отправил задачу при разборе. Удаление — не выбор места,
    /// его делает экран.
    nonisolated enum Choice: String, CaseIterable, Hashable, Sendable {
        case today
        case tomorrow
        case thisWeek
        /// «Оставить без даты»: задача остаётся во входящих, но больше не
        /// считается неразобранной.
        case keep

        var title: String {
            switch self {
            case .today: return "Сегодня"
            case .tomorrow: return "Завтра"
            case .thisWeek: return "На неделе"
            case .keep: return "Оставить без даты"
            }
        }
    }

    /// Подсказка Linea: куда задачу и почему.
    nonisolated struct Suggestion: Hashable, Sendable {
        let choice: Choice
        let reason: String
    }

    /// Предложение разобрать входящие — на экране «Сегодня».
    nonisolated struct Offer: Hashable, Sendable {
        let count: Int
        let text: String
    }

    let classifier: TaskClassifier

    init(classifier: TaskClassifier = TaskClassifier()) {
        self.classifier = classifier
    }

    // MARK: Что во входящих

    /// Во входящих — открытая задача без дня, срока и своего времени.
    static func isInInbox(_ task: LineaTask) -> Bool {
        !task.isDone && task.date == nil && task.deadline == nil && task.scheduledStart == nil
    }

    /// Входящие, давние — первыми.
    static func inbox(_ tasks: [LineaTask]) -> [LineaTask] {
        tasks.filter(isInInbox).sorted(by: DecisionEngine.chronological)
    }

    /// Неразобранные: человек ещё не решал, куда их.
    static func unsorted(_ tasks: [LineaTask]) -> [LineaTask] {
        inbox(tasks).filter { $0.inboxReviewedAt == nil }
    }

    // MARK: Когда предлагать

    /// Разбор стоит предложить, когда неразобранных накопилось три или одна
    /// лежит три дня. Иначе входящие не мешают — Linea молчит.
    func offer(tasks: [LineaTask], time: TimeContext) -> Offer? {
        let unsorted = Self.unsorted(tasks)
        guard !unsorted.isEmpty else { return nil }
        let staleBefore = time.adding(days: -Self.staleDays, to: time.today)
        let hasStale = unsorted.contains { $0.createdAt < staleBefore }
        guard unsorted.count >= Self.offerCount || hasStale else { return nil }
        let count = unsorted.count
        let noun = RussianText.plural(count, "задача", "задачи", "задач")
        return Offer(count: count, text: "\(count) \(noun) без даты — разберём за минуту?")
    }

    /// Подпись задачи «Без даты», которой Linea сама нашла время сегодня.
    static func plannedCaption(_ start: Date, time: TimeContext) -> String {
        "Linea нашла время: сегодня в \(RussianText.clock(start, time: time))"
    }

    // MARK: Подсказка

    /// Куда Linea советует задачу. `plannedStart` — Linea уже поставила её в
    /// свободное время сегодня.
    func suggestion(for task: LineaTask, goals: [LineaGoal], plannedStart: Date?, time: TimeContext) -> Suggestion {
        if let plannedStart {
            return Suggestion(
                choice: .today,
                reason: "Сегодня в \(RussianText.clock(plannedStart, time: time)) есть свободное время — я уже поставила её туда."
            )
        }
        let goal = task.goalID.flatMap { id in goals.first { $0.id == id && $0.isActive && !$0.isCompleted } }
        if let goal {
            return Suggestion(choice: .thisWeek, reason: "Шаг к цели \(RussianText.quoted(goal.title)) — лучше на этой неделе.")
        }
        switch task.priority {
        case .important:
            return Suggestion(choice: .tomorrow, reason: "Важная — лучше не откладывать надолго.")
        case .low:
            return Suggestion(choice: .keep, reason: "Не срочная — может полежать без даты.")
        case .normal:
            break
        }
        switch classifier.kind(of: task) {
        case .incoming:
            return Suggestion(choice: .tomorrow, reason: "Ответы лучше не держать долго.")
        case .obligation:
            return Suggestion(choice: .thisWeek, reason: "Обязательство — на этой неделе, день подберёт план.")
        case .goal, .maintenance, .routine, .standalone:
            return Suggestion(choice: .thisWeek, reason: "На этой неделе — день подберёт план.")
        }
    }

    // MARK: Выбор

    /// Задача после выбора: день и срок — как у «Сегодня», «Завтра», «На
    /// неделе» в быстром вводе. Задача помечается разобранной.
    func apply(_ choice: Choice, to task: LineaTask, profile: UserProfile, time: TimeContext) -> LineaTask {
        var task = task
        task.inboxReviewedAt = time.now
        let day: TaskDay
        switch choice {
        case .today: day = .today
        case .tomorrow: day = .tomorrow
        case .thisWeek: day = .thisWeek
        case .keep: return task
        }
        let resolved = day.resolve(time: time, profile: profile)
        task.date = resolved.date
        task.deadline = resolved.deadline
        return task
    }
}
