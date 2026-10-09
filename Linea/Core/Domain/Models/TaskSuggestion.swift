//
//  TaskSuggestion.swift
//  Linea
//
//  Предложение Linea: «Сейчас — вот это». Каждое предложение записывается в
//  день вместе с тем, что человек на него ответил: взялся («Начать») или
//  закрыл задачу — принято (`accepted = true`); «Не сейчас»; выбрал в
//  «Другое» иное; или Linea сама предложила другое, потому что сменилось
//  окно. Так копятся данные о том, как человек на самом деле принимает
//  советы — без этого их не научиться давать лучше.
//

import Foundation

nonisolated struct TaskSuggestion: Codable, Hashable, Sendable, Identifiable {
    nonisolated enum Response: String, Codable, Hashable, Sendable {
        /// «Начать» или задачу сделали — предложение принято.
        case accepted
        /// «Не сейчас» — или задачу убрали из планов.
        case declined
        /// В «Другое» выбрали иное дело.
        case otherChosen
        /// Ответа не было: Linea сама предложила другое (окно сменилось,
        /// началась встреча, кончился рабочий день).
        case replaced
    }

    let id: UUID
    let taskID: UUID
    let suggestedAt: Date
    /// Выбрано человеком в «Другое», а не предложено первым.
    let isAlternative: Bool
    /// Почему Linea это предложила — та же причина, что видел человек.
    let reason: NowReason?
    var response: Response?
    var respondedAt: Date?

    init(
        id: UUID,
        taskID: UUID,
        suggestedAt: Date,
        isAlternative: Bool = false,
        reason: NowReason? = nil,
        response: Response? = nil,
        respondedAt: Date? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.suggestedAt = suggestedAt
        self.isAlternative = isAlternative
        self.reason = reason
        self.response = response
        self.respondedAt = respondedAt
    }

    /// Ответа ещё нет: предложение на экране.
    var isOpen: Bool { response == nil }

    /// `accepted` из постановки: принято, не принято, ответа ещё нет.
    var accepted: Bool? { response.map { $0 == .accepted } }
}
