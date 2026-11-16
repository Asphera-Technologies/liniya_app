//
//  TaskFocus.swift
//  Linea
//
import Foundation

nonisolated struct TaskFocus: Hashable, Sendable, Identifiable {
    let taskID: UUID
    let title: String
    /// Сколько Linea отвела на дело, когда его начали.
    let minutes: Int
    let startedAt: Date
    /// «~45 мин».
    let duration: String
    /// «Начато в 11:20»; не сегодня — «Начато вчера в 17:05».
    let started: String

    var id: UUID { taskID }

    let timer: TaskTimer

    var isPaused: Bool { timer.pausedAt != nil }

    func remainingSeconds(at moment: Date) -> Int {
        timer.remainingSeconds(at: moment)
    }

    /// Таймер опирается на сохраненное время начала.
    static let hint = "Можно выйти из приложения — выполнение продолжается."
    /// Тихая ссылка под «Завершить»: то же, что «Не сейчас» у начатой.
    static let stopTitle = "Не получается продолжить"

    /// Фокус начатой задачи; nil — задача не начата, сделана или отменена.
    /// Сколько отведено — то, что Linea отвела при «Начать» (`ActionStart`);
    /// не записано — обычная длительность задачи с калибровкой.
    static func of(_ task: LineaTask, record: DayRecord?, calibration: Calibration, time: TimeContext) -> TaskFocus? {
        guard task.isOpen, let startedAt = task.startedAt else { return nil }
        let minutes = task.timer?.minutes ?? record.flatMap { allotted(to: task.id, startedAt: startedAt, in: $0) }
            ?? PlanDuration.minutes(for: task, calibration: calibration)
        return TaskFocus(
            taskID: task.id,
            title: task.title,
            minutes: minutes,
            startedAt: startedAt,
            duration: QuickTaskText.duration(minutes: minutes),
            started: startedText(startedAt, time: time),
            timer: task.timer ?? TaskTimer(minutes: minutes, startedAt: startedAt)
        )
    }

    /// Задача, фокус которой Linea показывает после запуска приложения:
    /// последняя начатая и не закрытая. Для старых записей без сохраненного
    /// таймера ограничиваем восстановление последними 12 часами.
    static func resumable(in tasks: [LineaTask], time: TimeContext) -> LineaTask? {
        let oldest = time.now.addingTimeInterval(-TimeInterval(TaskLifecycle.maxActualMinutes * 60))
        return tasks
            .filter { task in
                guard task.isOpen, let started = task.startedAt else { return false }
                return started <= time.now && (started >= oldest || task.timer != nil)
            }
            .max { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
    }

    /// «Начато в 11:20», «Начато вчера в 17:05», «Начато в пт, 3 окт».
    static func startedText(_ start: Date, time: TimeContext) -> String {
        let clock = RussianText.clock(start, time: time)
        if time.isSameDay(start, time.now) { return "Начато в \(clock)" }
        if time.isSameDay(start, time.adding(days: -1, to: time.today)) { return "Начато вчера в \(clock)" }
        return "Начато в " + RussianText.shortDay(start, time: time).lowercased()
    }

    /// Сколько было отведено при последнем «Начать» этой задачи: отклик
    /// пишется в ту же минуту, что и время начала.
    private static func allotted(to taskID: UUID, startedAt: Date, in record: DayRecord) -> Int? {
        record.feedback
            .compactMap { item -> (start: ActionStart, at: Date)? in
                guard case .actionStarted(let start) = item.kind, start.taskID == taskID else { return nil }
                return (start, item.at)
            }
            .filter { abs($0.at.timeIntervalSince(startedAt)) < 60 }
            .max { $0.at < $1.at }?
            .start.minutes
    }
}
