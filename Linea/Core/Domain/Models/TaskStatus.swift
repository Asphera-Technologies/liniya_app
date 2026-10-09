//
//  TaskStatus.swift
//  Linea
//
//  Состояние задачи — для данных, а не для экрана. Внутри Linea их семь:
//  во входящих, запланирована, предложена, начата, сделана, отложена,
//  отменена. Человек видит намного проще — три действия: «Начать»,
//  «Завершить», «Не сейчас» (`TaskLifecycle`).
//
//  Состояние не хранится отдельным полем, а выводится из того, что с задачей
//  было: `startedAt`, `completedAt`, `deferredUntil`, `cancelledAt`, день и
//  срок. Поэтому оно не расходится с ними. «Предложена» знает только тот, кто
//  предлагает, — это передаётся снаружи (действие «Сейчас»).
//

import Foundation

nonisolated enum TaskStatus: String, Codable, CaseIterable, Sendable {
    /// Записана без дня, срока и своего времени — во входящих.
    case inbox
    /// Есть день, срок или своё время.
    case planned
    /// Linea предлагает её прямо сейчас, а человек ещё не ответил.
    case suggested
    /// Человек нажал «Начать».
    case started
    /// Сделана: «Завершить», «Готово», итог дня.
    case completed
    /// «Не сейчас»: Linea не предлагает её до `deferredUntil`.
    case deferred
    /// Отменена: человек убрал её из планов.
    case cancelled
}

nonisolated extension LineaTask {
    /// Состояние в момент `moment`. `isSuggested` — Linea предлагает её сейчас.
    func status(at moment: Date, isSuggested: Bool = false) -> TaskStatus {
        if cancelledAt != nil { return .cancelled }
        if isDone { return .completed }
        if startedAt != nil { return .started }
        if let deferredUntil, deferredUntil > moment { return .deferred }
        if isSuggested { return .suggested }
        return date != nil || deadline != nil || scheduledStart != nil ? .planned : .inbox
    }

    /// Задача ещё в работе у человека: не сделана и не отменена.
    var isOpen: Bool { !isDone && cancelledAt == nil }

    /// «Не сейчас» ещё действует в этот момент.
    func isDeferred(at moment: Date) -> Bool {
        deferredUntil.map { $0 > moment } ?? false
    }
}
