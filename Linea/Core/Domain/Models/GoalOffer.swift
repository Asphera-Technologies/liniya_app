//
//  GoalOffer.swift
//  Linea
//
//  Мягкая поддержка целей на «Сегодня» — вопрос, а не упрёк:
//    • баланс дня (ADR-039): «Сегодня много текущих дел. Хочешь оставить
//      небольшое окно для цели «Запустить Линия Beta»?» [Оставить 30 минут]
//      [Не сегодня];
//    • возврат к цели (ADR-040): «По цели «Запустить Линия Beta» не было
//      действий четыре дня. Хочешь найти для неё небольшое окно завтра?» [Да]
//      [Пока нет].
//  Согласие ставит небольшое окно — задачу к цели на 30 минут; отказ
//  принимается без повторов: «Не сегодня» — до завтра, «Пока нет» — неделя.
//

import Foundation

nonisolated struct GoalOffer: Hashable, Sendable, Identifiable {
    nonisolated enum Kind: String, Codable, Hashable, Sendable {
        /// Много текущих дел, а шагов к важным целям сегодня нет.
        case balance
        /// Важная цель давно не двигалась.
        case returnAttention
    }

    let kind: Kind
    let goalID: UUID
    let goalTitle: String
    /// Сколько минут — окно для цели.
    let minutes: Int
    /// На какой день окно: сегодня (баланс) или завтра (возврат).
    let day: Date
    /// Что Linea заметила: «Сегодня много текущих дел.»
    let observation: String
    /// Вопрос: «Хочешь оставить небольшое окно для цели «…»?»
    let question: String
    /// Из чего состоит день — у баланса: «5 обязательств · 3 бытовых дела · 0 шагов к целям».
    let detail: String?
    /// «Оставить 30 минут» / «Да».
    let acceptTitle: String
    /// «Не сегодня» / «Пока нет».
    let declineTitle: String

    var id: String { "\(kind.rawValue)|\(goalID.uuidString)" }
}

/// Что человек ответил на предложение — пишется в день, как остальные отклики.
nonisolated struct GoalOfferAnswer: Codable, Hashable, Sendable {
    nonisolated enum Answer: String, Codable, Hashable, Sendable {
        case accepted
        case declined
    }

    let kind: GoalOffer.Kind
    let goalID: UUID
    let answer: Answer
    /// Окно, которое Linea поставила, если человек согласился.
    let taskID: UUID?

    init(kind: GoalOffer.Kind, goalID: UUID, answer: Answer, taskID: UUID? = nil) {
        self.kind = kind
        self.goalID = goalID
        self.answer = answer
        self.taskID = taskID
    }
}

nonisolated extension DayRecord {
    /// Ответы на предложения для целей в этот день.
    var goalOfferAnswers: [GoalOfferAnswer] {
        feedback.compactMap { item in
            if case .goalOffer(let answer) = item.kind { return answer }
            return nil
        }
    }

    /// День с ответом на предложение: ответ — в конце журнала, день не теряет
    /// ничего записанного раньше.
    func answering(_ answer: GoalOfferAnswer, at moment: Date) -> DayRecord {
        var record = self
        record.feedback.append(UserFeedback(at: moment, kind: .goalOffer(answer), planID: plan?.id))
        record.updatedAt = moment
        return record
    }
}
