//
//  GoalMatcher.swift
//  Linea
//
//  «Насколько задача мэтчится с целью» из брифа. Явная связь (`goalID`)
//  всегда сильнее: матчер только ПРЕДЛАГАЕТ связь в редакторе задачи и
//  никогда не проставляет её сам — иначе приоритизация перестанет быть
//  объяснимой.
//
//  В v1 это лексическое сравнение: детерминированно, работает офлайн и
//  проверяется тестами. On-device модель подключается позже как ещё одна
//  реализация этого протокола, без правок редактора и движков.
//

import Foundation

nonisolated struct GoalMatch: Hashable, Sendable {
    let goalID: UUID
    /// 0…1; чем выше, тем увереннее совпадение.
    let score: Double
}

nonisolated protocol GoalMatcher: Sendable {
    /// Лучшее совпадение среди целей или nil, если ничего похожего нет.
    func bestMatch(for taskTitle: String, in goals: [LineaGoal]) -> GoalMatch?
}

/// Совпадение по словам: доля общих значимых токенов (Жаккар) с бонусом за
/// общий корень. Русский язык морфологически богат, поэтому токены
/// обрезаются до основы фиксированной длины — «запустить/запуск» совпадут.
nonisolated struct KeywordGoalMatcher: GoalMatcher {
    /// Ниже этого порога подсказка не показывается.
    var threshold: Double
    /// Токены короче считаются служебными.
    var minimumTokenLength: Int
    /// До скольки символов обрезается токен, чтобы пережить окончания.
    var stemLength: Int

    init(threshold: Double = 0.2, minimumTokenLength: Int = 4, stemLength: Int = 5) {
        self.threshold = threshold
        self.minimumTokenLength = minimumTokenLength
        self.stemLength = stemLength
    }

    func bestMatch(for taskTitle: String, in goals: [LineaGoal]) -> GoalMatch? {
        let taskTokens = stems(of: taskTitle)
        guard !taskTokens.isEmpty else { return nil }

        let scored = goals
            .filter { $0.isActive && !$0.isCompleted }
            .map { goal in GoalMatch(goalID: goal.id, score: similarity(taskTokens, stems(of: goal.title))) }
            .filter { $0.score >= threshold }

        // Детерминированный выбор: выше score, при равенстве — меньший id.
        return scored.max { lhs, rhs in
            lhs.score != rhs.score ? lhs.score < rhs.score : lhs.goalID.uuidString > rhs.goalID.uuidString
        }
    }

    /// Жаккар по основам слов.
    func similarity(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let union = lhs.union(rhs).count
        guard union > 0 else { return 0 }
        return Double(lhs.intersection(rhs).count) / Double(union)
    }

    /// Значимые основы слов строки.
    func stems(of text: String) -> Set<String> {
        let separators = CharacterSet.alphanumerics.inverted
        let tokens = text.lowercased()
            .components(separatedBy: separators)
            .filter { $0.count >= minimumTokenLength }
        return Set(tokens.map { String($0.prefix(stemLength)) })
    }
}
