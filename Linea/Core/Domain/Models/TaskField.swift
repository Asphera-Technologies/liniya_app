//
//  TaskField.swift
//  Linea
//
//  Параметры задачи, которые может задать и человек, и Linea: день, срок,
//  время начала, длительность, приоритет, цель, сложность. Задача помнит,
//  какие из них задал человек (`LineaTask.userFields`): сказал словами при
//  создании, выбрал в чипе или поменял потом руками. Их Linea сама не
//  перезаписывает — ни правила, ни модель, если она появится (`TaskOwnership`).
//
//  Название всегда человека, поэтому его здесь нет. Тип задачи хранит выбор
//  человека отдельно (`LineaTask.kindOverride`).
//

import Foundation

nonisolated enum TaskField: String, Codable, CaseIterable, Hashable, Sendable {
    /// День задачи (`date`), в том числе «Без даты», выбранное человеком.
    case day
    case deadline
    /// Время начала (`scheduledStart`).
    case startTime
    /// Сколько займёт (`estimatedMinutes`).
    case duration
    case priority
    /// Цель, в том числе «Без цели», выбранное человеком.
    case goal
    /// Сложность (`cognitiveDemand`).
    case demand
}
