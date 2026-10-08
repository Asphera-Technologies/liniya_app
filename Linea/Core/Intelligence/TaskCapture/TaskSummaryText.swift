//
//  TaskSummaryText.swift
//  Linea
//
//  Задача одной строкой: «Завтра · до 12:00 · ~1 ч 30 мин · Высокий». Так
//  быстрый ввод показывает, как Linea поняла сказанное, а список — что у
//  задачи задано. В строке только то, что есть: чего не сказали и не
//  выбрали, того нет — ни «Средний» по умолчанию, ни обычной длительности.
//

import Foundation

nonisolated extension QuickTaskText {

    /// Как Linea поняла строку быстрого ввода — без значений по умолчанию.
    static func summary(_ resolution: QuickTaskResolution, time: TimeContext) -> String {
        var parts: [String] = []
        if resolution.dayOrigin != .assumed {
            if let date = resolution.date {
                parts.append(dayName(date, time: time))
            } else if resolution.day == .thisWeek, resolution.deadline == nil || resolution.isEndOfWeekDeadline {
                parts.append("На неделе")
            }
        }
        if let start = resolution.scheduledStart {
            parts.append("в \(RussianText.clock(start, time: time))")
        }
        if let deadline = resolution.deadline, resolution.deadlineOrigin != .assumed, !resolution.isEndOfWeekDeadline {
            parts.append(deadlinePart(deadline, day: resolution.date, time: time))
        }
        if let minutes = resolution.minutes {
            parts.append(duration(minutes: minutes))
        }
        if resolution.priorityOrigin != .assumed {
            parts.append(resolution.priority.title)
        }
        return parts.joined(separator: separator)
    }

    /// Что задано у сохранённой задачи. В «Плане» день уже в заголовке
    /// раздела, а приоритет — справа в строке, поэтому их можно не повторять.
    static func summary(of task: LineaTask, time: TimeContext, includesDay: Bool = true, includesPriority: Bool = true) -> String {
        var parts: [String] = []
        if includesDay, let date = task.date {
            parts.append(dayName(date, time: time))
        }
        if let start = task.scheduledStart {
            parts.append("в \(RussianText.clock(start, time: time))")
        }
        if let deadline = task.deadline {
            parts.append(deadlinePart(deadline, day: task.date, time: time))
        }
        if let minutes = task.estimatedMinutes {
            parts.append(duration(minutes: minutes))
        }
        if includesPriority, task.priority != .normal || task.userFields?.contains(.priority) == true {
            parts.append(task.priority.title)
        }
        return parts.joined(separator: separator)
    }

    static let separator = " · "

    /// «до 12:00» в день задачи (а без дня — сегодня), иначе «до пт, 11 сен».
    private static func deadlinePart(_ deadline: Date, day: Date?, time: TimeContext) -> String {
        if let day, time.isSameDay(deadline, day) {
            return "до \(RussianText.clock(deadline, time: time))"
        }
        return Self.deadline(deadline, time: time)
    }
}
