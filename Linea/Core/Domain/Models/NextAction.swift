//
//  NextAction.swift
//  Linea
//
//  Действие «сейчас» — отдельная сущность, не задача. У задачи своя жизнь:
//  день, срок, приоритет, цель. У действия — момент, окно, сколько на него
//  отвести и что человек с ним сделал: начал, выбрал другое, закрыл. Linea
//  предлагает одно действие и по просьбе («Другое») ещё два-три — длинный
//  ранжированный список человек не видит.
//

import Foundation

nonisolated struct NextAction: Hashable, Sendable {
    /// Задача в роли действия: что делать и сколько на это отвести сейчас.
    nonisolated struct Option: Hashable, Sendable, Identifiable {
        let taskID: UUID
        let title: String
        /// «~15 мин».
        let minutes: Int

        var id: UUID { taskID }
    }

    /// Что Linea предлагает сейчас; nil — сейчас ни одно не помещается.
    let option: Option?
    /// «Другое»: не больше трёх задач, которые тоже уместны сейчас.
    let alternatives: [Option]
    /// Важная задача, которой сейчас не хватает окна: «её лучше после».
    let laterTaskID: UUID?
    /// Человек уже взялся за действие — с этого момента.
    let startedAt: Date?
    /// Фраза вместо названия задачи, когда предлагать нечего: «До встречи
    /// осталось 10 мин — короткая пауза.»
    let headline: String
    /// Почему сейчас это — одна короткая фраза без баллов (`NowReason`):
    /// «Высокий приоритет, а срок — сегодня вечером.» У начатого — «Начато в
    /// 11:40.»
    let reason: String
    let facts: [Fact]

    var taskID: UUID? { option?.taskID }
    var isStarted: Bool { startedAt != nil }
}

/// «Начать»: человек взялся за действие. Пишется в день как отклик
/// (`FeedbackKind.actionStarted`); сама задача при этом не меняется.
nonisolated struct ActionStart: Codable, Hashable, Sendable {
    let taskID: UUID
    /// Сколько Linea отвела на действие.
    let minutes: Int
    /// Выбрано в «Другое», а не рекомендованное.
    let wasAlternative: Bool
}

nonisolated extension DayRecord {
    /// Начатое действие, которое ещё идёт: задача не закрыта, и с начала
    /// прошло не больше полутора отведённых длительностей (и хотя бы 15 минут
    /// сверх отведённого). Новое «Начать» сменяет прежнее.
    func activeAction(tasks: [LineaTask], at moment: Date) -> (start: ActionStart, at: Date)? {
        let started = feedback.compactMap { item -> (start: ActionStart, at: Date)? in
            if case .actionStarted(let start) = item.kind { return (start, item.at) }
            return nil
        }
        guard let last = started.max(by: { $0.at < $1.at }), last.at <= moment else { return nil }
        guard let task = tasks.first(where: { $0.id == last.start.taskID }), !task.isDone else { return nil }
        let allowed = max(Double(last.start.minutes) * 1.5, Double(last.start.minutes + 15))
        return moment.timeIntervalSince(last.at) <= allowed * 60 ? last : nil
    }
}
