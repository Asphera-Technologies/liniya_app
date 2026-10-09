//
//  TaskExecutionText.swift
//  Linea
//
//  Как выполнение задачи видно человеку: одна строка без внутренних
//  состояний — «В работе с 10:12», «Сделано в 11:05 · за 35 мин», «Не сейчас
//  — до 12:30». В карточке задачи и под строкой списка. Здесь, а не в
//  экране: так текст проверяют тесты, а формат времени тот же, что во всех
//  текстах Linea (`RussianText`).
//

import Foundation

nonisolated enum TaskExecutionText {

    /// Строка о выполнении в карточке задачи; nil — сказать нечего: задача
    /// просто запланирована или лежит во входящих.
    static func status(of task: LineaTask, time: TimeContext) -> String? {
        switch task.status(at: time.now) {
        case .started:
            guard let start = task.startedAt else { return nil }
            if time.isSameDay(start, time.now) { return "В работе с \(RussianText.clock(start, time: time))" }
            return "Начата \(moment(start, time: time))"
        case .completed:
            var text = "Сделано"
            if let completedAt = task.completedAt { text += " \(moment(completedAt, time: time))" }
            if let minutes = task.actualMinutes { text += " · за \(RussianText.duration(minutes: minutes))" }
            return text
        case .deferred:
            guard let until = task.deferredUntil else { return nil }
            let clock = RussianText.clock(until, time: time)
            return time.isSameDay(until, time.now) ? "Не сейчас — до \(clock)" : "Не сейчас — до завтра, \(clock)"
        case .inbox, .planned, .suggested, .cancelled:
            return nil
        }
    }

    /// Подпись под строкой списка: только то, что меняет дело сейчас, —
    /// задача в работе или отложена. Сделанную и так видно по галочке.
    static func caption(of task: LineaTask, time: TimeContext) -> String? {
        switch task.status(at: time.now) {
        case .started, .deferred: return status(of: task, time: time)
        case .inbox, .planned, .suggested, .completed, .cancelled: return nil
        }
    }

    /// «в 11:05» сегодня, «вчера в 11:05», раньше — «в пт, 3 окт».
    private static func moment(_ date: Date, time: TimeContext) -> String {
        let clock = RussianText.clock(date, time: time)
        if time.isSameDay(date, time.now) { return "в \(clock)" }
        if time.isSameDay(date, time.adding(days: -1, to: time.today)) { return "вчера в \(clock)" }
        return "в " + RussianText.shortDay(date, time: time).lowercased()
    }
}
