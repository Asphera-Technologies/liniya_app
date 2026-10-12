//
//  QuickGoalDraft.swift
//  Linea
//
//  Быстрая цель, как быстрая задача (ADR-035): не форма, а один вопрос —
//  «Чего хочешь достичь?». Строка «Выпустить Линия в TestFlight до 15-го
//  октября» → название «Выпустить Линия в TestFlight», срок 15 октября, тип
//  — проект, прогресс — этапами. Под строкой — чипы самого важного: срок,
//  важность, как считать прогресс, сфера. Выбор в чипе сильнее сказанного,
//  сказанное — того, что Linea решила сама. «Создать цель» — и всё; рассказ,
//  «Сейчас», признаки успеха — по желанию, «Рассказать подробнее».
//
//  Чистая функция: экран показывает `QuickGoalResolution`, тесты проверяют
//  путь «строка → цель» без телефона.
//

import Foundation

nonisolated struct QuickGoalDraft: Hashable, Sendable {
    nonisolated enum DeadlineChoice: Hashable, Sendable {
        case at(Date)
        /// «Без срока».
        case noDeadline
    }

    var text: String
    // Выбор в чипах. nil — чип не трогали.
    var deadline: DeadlineChoice?
    var priority: TaskPriority?
    var method: GoalProgressMethod?
    var scope: GoalScope?

    init(
        text: String = "",
        deadline: DeadlineChoice? = nil,
        priority: TaskPriority? = nil,
        method: GoalProgressMethod? = nil,
        scope: GoalScope? = nil
    ) {
        self.text = text
        self.deadline = deadline
        self.priority = priority
        self.method = method
        self.scope = scope
    }

    var hasChoices: Bool { deadline != nil || priority != nil || method != nil || scope != nil }

    func resolve(
        profile: UserProfile,
        time: TimeContext,
        analyzer: RuleBasedGoalAnalyzer = RuleBasedGoalAnalyzer()
    ) -> QuickGoalResolution {
        let understood = analyzer.understand(GoalIntakeInput(title: text), profile: profile, time: time)
        return resolution(of: understood)
    }

    /// Что получится из понятого с выбором в чипах. Тем же путём проходит и
    /// «Рассказать подробнее»: выбор, сделанный в быстрой цели, не теряется.
    func resolution(of understood: GoalUnderstanding) -> QuickGoalResolution {
        var understanding = understood
        var result = QuickGoalResolution(understanding: understood)

        switch deadline {
        case .at(let moment)?:
            understanding.deadline = moment
            result.deadlineOrigin = .chosen
        case .noDeadline?:
            understanding.deadline = nil
            result.deadlineOrigin = .chosen
        case nil:
            result.deadlineOrigin = understood.deadline == nil ? .assumed : .typed
        }

        if let priority {
            understanding.priority = priority
            understanding.isPrioritySaid = true
            result.priorityOrigin = .chosen
        } else {
            result.priorityOrigin = understood.isPrioritySaid ? .typed : .assumed
        }

        if let method {
            understanding.method = method
            result.methodOrigin = .chosen
        }

        if let scope {
            understanding.scope = scope
            understanding.isScopeChosen = true
            result.scopeOrigin = .chosen
        }

        result.understanding = understanding
        return result
    }
}

/// Что получится из быстрой цели прямо сейчас — это и показывают чипы.
nonisolated struct QuickGoalResolution: Hashable, Sendable {
    typealias Origin = QuickTaskResolution.Origin

    var understanding: GoalUnderstanding
    var deadlineOrigin: Origin = .assumed
    var priorityOrigin: Origin = .assumed
    /// Как считать прогресс: решила Linea (`assumed`) или выбрал человек.
    var methodOrigin: Origin = .assumed
    var scopeOrigin: Origin = .assumed

    init(understanding: GoalUnderstanding) {
        self.understanding = understanding
    }

    var title: String { understanding.title }
    var canCreate: Bool { understanding.canCreate }

    /// Linea что-то поняла из слов и вырезала это из названия — тогда экран
    /// показывает цель так, как она сохранится.
    var isUnderstood: Bool { understanding.isTitleUnderstood }

    func goal(id: UUID, createdAt: Date, time: TimeContext) -> LineaGoal {
        understanding.goal(id: id, createdAt: createdAt, time: time)
    }
}

/// Быстрые сроки в чипе цели; остальное — «Выбрать дату…».
nonisolated enum GoalDeadlineOption: CaseIterable, Hashable, Sendable {
    case inAMonth
    case inThreeMonths
    case endOfYear

    var title: String {
        switch self {
        case .inAMonth: return "Через месяц"
        case .inThreeMonths: return "Через 3 месяца"
        case .endOfYear: return "До конца года"
        }
    }

    /// День срока.
    func date(time: TimeContext) -> Date {
        let calendar = time.calendar
        let today = time.today
        switch self {
        case .inAMonth:
            return calendar.date(byAdding: .month, value: 1, to: today).map(time.startOfDay) ?? time.adding(days: 30, to: today)
        case .inThreeMonths:
            return calendar.date(byAdding: .month, value: 3, to: today).map(time.startOfDay) ?? time.adding(days: 91, to: today)
        case .endOfYear:
            var components = DateComponents()
            components.year = calendar.component(.year, from: today) + 1
            components.month = 1
            components.day = 1
            let next = calendar.date(from: components).map(time.startOfDay) ?? time.adding(days: 365, to: today)
            return time.adding(days: -1, to: next)
        }
    }
}

/// Подписи быстрой цели. Здесь, а не в экране, — их проверяют тесты.
nonisolated enum QuickGoalText {
    /// Пункт быстрого срока: «Через месяц · 9 окт».
    static func deadlineOption(_ option: GoalDeadlineOption, time: TimeContext) -> String {
        "\(option.title)\(GoalProgressText.separator)\(GoalProgressText.shortDate(option.date(time: time), time: time))"
    }

    /// Как Linea поняла строку — только сказанное и выбранное: «до 15
    /// октября · Высокая». Значений по умолчанию здесь нет.
    static func summary(_ resolution: QuickGoalResolution, time: TimeContext) -> String {
        var parts: [String] = []
        if resolution.deadlineOrigin != .assumed, let deadline = resolution.understanding.deadline {
            parts.append(GoalProgressText.deadline(deadline, time: time))
        }
        if resolution.priorityOrigin != .assumed {
            parts.append(LineaGoal.importanceTitle(resolution.understanding.priority))
        }
        return parts.joined(separator: GoalProgressText.separator)
    }

    /// Чип срока: «до 15 окт» или «Без срока».
    static func deadlineChip(_ resolution: QuickGoalResolution, time: TimeContext) -> String {
        guard let deadline = resolution.understanding.deadline else { return "Без срока" }
        return GoalProgressText.shortDeadline(deadline, time: time)
    }

    /// Чип прогресса: «Этапы»; у числа — что считаем: «Число · 50 пользователей».
    static func methodChip(_ resolution: QuickGoalResolution) -> String {
        let understanding = resolution.understanding
        if understanding.method == .metric, let metric = understanding.metrics.first {
            return understanding.method.title + GoalProgressText.separator + GoalProgressText.amount(metric.target, unit: metric.unit)
        }
        return understanding.method.title
    }
}
