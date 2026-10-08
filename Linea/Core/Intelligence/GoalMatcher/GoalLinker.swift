//
//  GoalLinker.swift
//  Linea
//
//  Кто связывает задачу с целью. Три источника связи, от сильного к слабому:
//    • человек — выбрал цель в чипе или сказал «для цели …»;
//    • Linea сама — когда совпадение уверенное и политика это разрешает;
//    • подсказка — «похоже, это к цели …», связывает человек.
//
//  Политика — только подсказка: так просил заказчик («Похоже, относится к: …
//  [Связать]»; ничего не нажал — задача спокойно живёт без цели). Автосвязь
//  заложена политикой `.automatic` и выключена.
//

import Foundation

nonisolated struct GoalLink: Hashable, Sendable {
    nonisolated enum Source: String, Hashable, Sendable {
        /// Человек сказал сам: «для цели …» или выбрал в чипе.
        case explicit
        /// Похоже по словам — Linea предлагает, связывает человек.
        case suggested
        /// Похоже настолько, что Linea связала сама.
        case automatic
    }

    let goalID: UUID
    let source: Source
    /// 0…1; для явной связи — 1.
    let score: Double
}

nonisolated struct GoalLinker: Sendable {
    nonisolated enum Policy: Hashable, Sendable {
        /// Связь ставит только человек, Linea подсказывает.
        case suggestOnly
        /// Совпадение не слабее порога связывается само; человек может снять.
        case automatic(minimumScore: Double)
    }

    /// Связь ставит человек (ADR-023, ADR-033).
    static let defaultPolicy: Policy = .suggestOnly
    /// Порог автосвязи, когда её включат: заметно увереннее подсказки.
    static let automaticScore = 0.8

    let matcher: any GoalMatcher
    let policy: Policy

    init(matcher: any GoalMatcher = ConceptGoalMatcher(), policy: Policy = GoalLinker.defaultPolicy) {
        self.matcher = matcher
        self.policy = policy
    }

    /// Подсказка для сохранённой задачи: «Похоже, относится к: … [Связать]».
    /// Не нужна, если цель уже есть или человек сам выбрал «Без цели» — его
    /// решение Linea не переспрашивает.
    func suggestion(for task: LineaTask, goals: [LineaGoal]) -> GoalLink? {
        guard !task.isDone, task.goalID == nil, task.userFields?.contains(.goal) != true else { return nil }
        guard let match = matcher.bestMatch(for: task.title, in: goals) else { return nil }
        return GoalLink(goalID: match.goalID, source: .suggested, score: match.score)
    }

    /// Связь по названию задачи: автоматическая или подсказка. Nil — ничего похожего.
    func link(forTitle title: String, goals: [LineaGoal]) -> GoalLink? {
        guard let match = matcher.bestMatch(for: title, in: goals) else { return nil }
        if case .automatic(let minimumScore) = policy, match.score >= minimumScore {
            return GoalLink(goalID: match.goalID, source: .automatic, score: match.score)
        }
        return GoalLink(goalID: match.goalID, source: .suggested, score: match.score)
    }
}
