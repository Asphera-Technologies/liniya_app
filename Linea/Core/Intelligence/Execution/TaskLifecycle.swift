//
//  TaskLifecycle.swift
//  Linea
//
//  Что происходит с задачей, когда человек с ней что-то делает. В интерфейсе
//  три действия:
//    • «Начать»    — `startedAt`; если это было предложение Linea — его id;
//    • «Завершить» — `completedAt` и сколько заняло на самом деле
//                    (`actualMinutes`, от «Начать» до «Завершить»);
//    • «Не сейчас» — Linea не предлагает и не ставит задачу в план полтора
//                    часа; начатая перестаёт быть начатой.
//  И служебные: отменить (убрать из планов, «Удалить»), вернуть закрытую и
//  снять «в работе», когда человек начал другое дело — в работе всегда одно.
//  Внутреннее состояние (`TaskStatus`) следует из этих полей само.
//
//  Чистые функции: переход, которого не бывает (начать сделанную, завершить
//  отменённую), возвращает nil — задача не меняется.
//

import Foundation

nonisolated struct TaskLifecycle: Sendable {
    /// «Не сейчас»: столько Linea не предлагает задачу снова.
    static let notNowMinutes = 90
    /// Дольше — забыли нажать «Завершить»: сколько заняло, неизвестно.
    static let maxActualMinutes = 12 * 60

    init() {}

    /// «Начать». `suggestionID` — предложение Linea, которое человек принял.
    /// Начатую задачу можно начать снова — отсчёт пойдёт заново.
    func start(_ task: LineaTask, suggestionID: UUID?, at moment: Date) -> LineaTask? {
        guard task.isOpen else { return nil }
        var result = task
        result.startedAt = moment
        result.deferredUntil = nil
        result.suggestionID = suggestionID
        return result
    }

    /// «Завершить», «Готово». Сколько заняло — только если начинали.
    /// `suggestionID` — задачу закрыли, пока Linea её предлагала.
    func finish(_ task: LineaTask, suggestionID: UUID?, at moment: Date) -> LineaTask? {
        guard task.isOpen else { return nil }
        var result = task
        result.isDone = true
        result.completedAt = moment
        result.actualMinutes = task.startedAt.flatMap { Self.actualMinutes(from: $0, to: moment) }
        result.deferredUntil = nil
        if let suggestionID { result.suggestionID = suggestionID }
        return result
    }

    /// Взялся за другое дело: в работе одно — прежнее перестаёт быть
    /// начатым, но не откладывается. Предложение, из которого его начали,
    /// остаётся при нём: от него не отказывались.
    func pause(_ task: LineaTask) -> LineaTask? {
        guard task.isOpen, task.startedAt != nil else { return nil }
        var result = task
        result.startedAt = nil
        return result
    }

    /// «Не сейчас». Начатая перестаёт быть начатой: человек отложил её.
    func notNow(_ task: LineaTask, at moment: Date) -> LineaTask? {
        guard task.isOpen else { return nil }
        var result = task
        result.startedAt = nil
        result.suggestionID = nil
        result.deferredUntil = moment.addingTimeInterval(TimeInterval(Self.notNowMinutes * 60))
        return result
    }

    /// Убрать из планов («Удалить»). Задача остаётся в данных.
    func cancel(_ task: LineaTask, at moment: Date) -> LineaTask? {
        guard task.cancelledAt == nil else { return nil }
        var result = task
        result.cancelledAt = moment
        result.deferredUntil = nil
        return result
    }

    /// Вернуть закрытую: снова открыта и не начата.
    func reopen(_ task: LineaTask) -> LineaTask? {
        guard task.isDone, task.cancelledAt == nil else { return nil }
        var result = task
        result.isDone = false
        result.completedAt = nil
        result.actualMinutes = nil
        result.startedAt = nil
        result.suggestionID = nil
        return result
    }

    /// Минуты от «Начать» до «Завершить», не меньше одной. Больше
    /// `maxActualMinutes` или назад во времени — неизвестно.
    static func actualMinutes(from start: Date, to end: Date) -> Int? {
        let seconds = end.timeIntervalSince(start)
        guard seconds >= 0 else { return nil }
        let minutes = Int((seconds / 60).rounded())
        guard minutes <= maxActualMinutes else { return nil }
        return max(1, minutes)
    }
}
