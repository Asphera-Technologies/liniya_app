//
//  QuickTaskDraft.swift
//  Linea
//
//  Быстрый ввод целиком: строка, которую человек набрал или надиктовал, и то,
//  что он выбрал в чипах под ней. Название — единственное обязательное;
//  остальное берётся из чипа, иначе из строки, иначе — значение по умолчанию.
//  Всё можно поменять потом в карточке задачи.
//
//  Чистая функция: экран показывает `QuickTaskResolution`, «Добавить»
//  сохраняет её `task(id:createdAt:)`, а тесты проверяют путь «строка →
//  задача» без телефона.
//

import Foundation

nonisolated struct QuickTaskDraft: Hashable, Sendable {
    nonisolated enum GoalChoice: Hashable, Sendable {
        case linked(UUID)
        /// «Без цели» — сильнее и сказанного, и подсказки.
        case noGoal
    }

    nonisolated enum DeadlineChoice: Hashable, Sendable {
        case at(Date)
        /// «Без срока».
        case noDeadline
    }

    var text: String
    // Выбор в чипах. `nil` — чип не трогали.
    var day: TaskDay?
    var deadline: DeadlineChoice?
    var minutes: Int?
    var priority: TaskPriority?
    var goal: GoalChoice?

    init(
        text: String = "",
        day: TaskDay? = nil,
        deadline: DeadlineChoice? = nil,
        minutes: Int? = nil,
        priority: TaskPriority? = nil,
        goal: GoalChoice? = nil
    ) {
        self.text = text
        self.day = day
        self.deadline = deadline
        self.minutes = minutes
        self.priority = priority
        self.goal = goal
    }

    func resolve(
        goals: [LineaGoal],
        profile: UserProfile,
        time: TimeContext,
        defaultDay: TaskDay? = .someday,
        parser: QuickTaskParser = QuickTaskParser(),
        linker: GoalLinker = GoalLinker(),
        classifier: TaskClassifier = TaskClassifier()
    ) -> QuickTaskResolution {
        let activeGoals = goals.filter { $0.isActive && !$0.isCompleted }
        let parsed = parser.parse(text, goals: activeGoals, profile: profile, time: time)
        var result = QuickTaskResolution(title: parsed.title.trimmingCharacters(in: .whitespacesAndNewlines))

        // Когда. Срок без дня («отчёт к пятнице») — задача без дня: в какой
        // день за неё взяться, решит план. Ни дня, ни срока не назвали —
        // «Без даты» (входящие, §18): «Когда?» Linea не спрашивает.
        let deadlineGiven: Bool
        switch deadline {
        case .at?: deadlineGiven = true
        case .noDeadline?: deadlineGiven = false
        case nil: deadlineGiven = parsed.deadline != nil
        }
        if let day {
            result.day = day
            result.dayOrigin = .chosen
        } else if let typed = parsed.day {
            result.day = typed
            result.dayOrigin = .typed
        } else if let start = parsed.startTime {
            // «Позвонить в 19:00»: сегодня, а если время прошло — завтра.
            let today = time.date(on: time.today, at: start)
            result.day = today > time.now ? .today : .tomorrow
            result.dayOrigin = .typed
        } else if deadlineGiven {
            result.day = nil
            result.dayOrigin = deadline == nil ? .typed : .chosen
        } else {
            result.day = defaultDay
            result.dayOrigin = .assumed
        }
        let resolvedDay = result.day?.resolve(time: time, profile: profile) ?? (date: nil, deadline: nil)
        result.date = resolvedDay.date

        switch deadline {
        case .at(let moment)?:
            result.deadline = moment
            result.deadlineOrigin = .chosen
        case .noDeadline?:
            result.deadline = nil
            result.deadlineOrigin = .chosen
        case nil:
            if let typed = parsed.deadline {
                result.deadline = typed
                result.deadlineOrigin = .typed
            } else {
                // «На неделе» — срок конца недели.
                result.deadline = resolvedDay.deadline
                result.deadlineOrigin = resolvedDay.deadline == nil ? .assumed : result.dayOrigin
                result.isEndOfWeekDeadline = resolvedDay.deadline != nil
            }
        }

        // Время начала живёт на дне задачи: сменили день — время переехало.
        if let start = parsed.startTime, let date = result.date {
            result.scheduledStart = time.date(on: date, at: start)
        }

        if let minutes {
            result.minutes = minutes
            result.minutesOrigin = .chosen
        } else if let typed = parsed.minutes {
            result.minutes = typed
            result.minutesOrigin = .typed
        }

        if let priority {
            result.priority = priority
            result.priorityOrigin = .chosen
        } else if let typed = parsed.priority {
            result.priority = typed
            result.priorityOrigin = .typed
        }

        switch goal {
        case .linked(let id)?:
            result.goalID = id
            result.goalOrigin = .chosen
        case .noGoal?:
            result.goalOrigin = .chosen
        case nil:
            if let typed = parsed.goalID {
                result.goalID = typed
                result.goalOrigin = .typed
            } else if let link = linker.link(forTitle: result.title, goals: activeGoals) {
                switch link.source {
                case .automatic:
                    result.goalID = link.goalID
                    result.goalOrigin = .assumed
                case .suggested, .explicit:
                    result.suggestion = link
                }
            }
        }

        // Тип — по тому, что получилось: связь с целью делает задачу шагом к
        // цели. От типа — сложность, если человек её не назвал, и оценка
        // длительности, которую покажет серый чип.
        result.kind = classifier.classify(
            title: result.title, goalID: result.goalID,
            isFixed: result.scheduledStart != nil, demand: parsed.demand
        ).kind
        result.demand = parsed.demand ?? result.kind.typicalDemand

        result.recognized = parsed.recognized
        return result
    }
}

/// Что получится из быстрого ввода прямо сейчас — это и показывают чипы.
nonisolated struct QuickTaskResolution: Hashable, Sendable {
    /// Откуда значение: от него зависит, как чип выглядит.
    nonisolated enum Origin: Hashable, Sendable {
        /// Распознано в строке.
        case typed
        /// Выбрано в чипе.
        case chosen
        /// Не задано: значение по умолчанию или решение Linea.
        case assumed
    }

    var title: String
    var day: TaskDay?
    var dayOrigin: Origin = .assumed
    var date: Date?
    var deadline: Date?
    var deadlineOrigin: Origin = .assumed
    /// Срок — просто конец недели из «на неделе», а не названный отдельно.
    var isEndOfWeekDeadline = false
    var scheduledStart: Date?
    /// Nil — человек не сказал; план возьмёт свою оценку.
    var minutes: Int?
    var minutesOrigin: Origin = .assumed
    var priority: TaskPriority = .normal
    var priorityOrigin: Origin = .assumed
    var demand: CognitiveDemand = .normal
    /// Какого типа задача — внутреннее, в интерфейсе не показывается.
    var kind: TaskKind = .standalone
    var goalID: UUID?
    var goalOrigin: Origin = .assumed
    /// «Похоже, это к цели …» — когда цель не выбрана.
    var suggestion: GoalLink?
    var recognized: [QuickTaskParse.Recognized] = []

    init(title: String) {
        self.title = title
    }

    var canSave: Bool { !title.isEmpty }

    /// Сколько займёт: сказанное или обычное для типа задачи.
    var estimatedMinutes: Int { minutes ?? kind.typicalMinutes }

    /// Задача, которую сохранит «Добавить».
    func task(id: UUID, createdAt: Date) -> LineaTask {
        LineaTask(
            id: id,
            title: title,
            date: date,
            priority: priority,
            createdAt: createdAt,
            deadline: deadline,
            scheduledStart: scheduledStart,
            estimatedMinutes: minutes,
            cognitiveDemand: demand,
            goalID: goalID
        )
    }
}

/// Подписи чипов. Здесь, а не в экране: так их проверяют тесты, а формат
/// дат тот же, что во всех текстах Linea (`RussianText`).
nonisolated enum QuickTaskText {

    /// «Сегодня», «Завтра, 15:00», «Пт, 3 окт», «На неделе», «до 18:00», «Без даты».
    static func day(_ resolution: QuickTaskResolution, time: TimeContext) -> String {
        if let date = resolution.date {
            var text = dayName(date, time: time)
            if let start = resolution.scheduledStart {
                text += ", \(RussianText.clock(start, time: time))"
            } else if let deadline = resolution.deadline, time.isSameDay(deadline, date) {
                text += ", до \(RussianText.clock(deadline, time: time))"
            }
            return text
        }
        // «На неделе» — пока срок не назвали отдельно: «на неделе, до 18:00
        // сегодня» показывает срок, а не неделю.
        if resolution.day == .thisWeek, resolution.deadline == nil || resolution.isEndOfWeekDeadline {
            return "На неделе"
        }
        if let deadline = resolution.deadline {
            return Self.deadline(deadline, time: time)
        }
        return "Без даты"
    }

    /// Срок задачи без дня: «до 18:00» сегодня, иначе «до завтра», «до пт, 11 сен».
    static func deadline(_ deadline: Date, time: TimeContext) -> String {
        if time.isSameDay(deadline, time.now) { return "до \(RussianText.clock(deadline, time: time))" }
        return "до " + dayName(deadline, time: time).lowercased()
    }

    /// «Сегодня», «Завтра» или «Пт, 3 окт».
    static func dayName(_ date: Date, time: TimeContext) -> String {
        if time.isSameDay(date, time.today) { return "Сегодня" }
        if time.isSameDay(date, time.adding(days: 1, to: time.today)) { return "Завтра" }
        return RussianText.shortDay(date, time: time)
    }

    /// «~30 мин», «~1 ч», «~1 ч 30 мин».
    static func duration(minutes: Int) -> String {
        "~" + RussianText.duration(minutes: minutes)
    }
}
