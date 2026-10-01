//
//  GoalLinker.swift
//  Linea
//
//  Кто связывает задачу с целью. Три источника связи, от сильного к слабому:
//    • человек — выбрал цель в чипе или сказал «для цели …»;
//    • Linea сама — когда совпадение уверенное и политика это разрешает;
//    • подсказка — «похоже, это к цели …», связывает человек.
//
//  Сейчас политика — только подсказка (ADR-023): связь меняет приоритет
//  задачи, и пусть её ставит человек, пока совпадение по словам — всё, что
//  Linea умеет. Автосвязь включается одной строкой, когда матчер станет
//  умнее (модель на телефоне — ещё одна реализация `GoalMatcher`).
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

    /// Сейчас связь ставит человек (ADR-023).
    static let defaultPolicy: Policy = .suggestOnly
    /// Порог автосвязи, когда её включат: половина значимых слов — общие.
    static let automaticScore = 0.5

    let matcher: any GoalMatcher
    let policy: Policy

    init(matcher: any GoalMatcher = KeywordGoalMatcher(), policy: Policy = GoalLinker.defaultPolicy) {
        self.matcher = matcher
        self.policy = policy
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
