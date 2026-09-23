//
//  CheckInDraft.swift
//  Linea
//
//  То, что человек видит на экране «Проверь»: задачи с галочками, сделанное
//  сверх плана, объём, оценка дня, что Linea предлагает запомнить. Черновик
//  строится из разбора, человек правит галочки, и только потом
//  `SubmitCheckInUseCase` что-то меняет. Ничего не отмечается без него.
//

import Foundation

nonisolated struct CheckInDraft: Sendable, Equatable {

    nonisolated struct TaskLine: Sendable, Equatable, Identifiable {
        let id: UUID
        let title: String
        let minutes: Int
        /// Задача была назначена на этот день.
        let isPlannedForDay: Bool
        /// Задача была закрыта ещё до итога — галочку с неё здесь не снимают.
        let wasDone: Bool
        /// Что понято из рассказа; `nil` — о задаче не говорили.
        let understood: TaskOutcomeStatus?
        let isConfident: Bool
        /// Галочка на экране.
        var isDone: Bool

        /// Подпись под задачей: что Linea услышала.
        var note: String? {
            if wasDone { return "уже была закрыта" }
            guard let understood else { return nil }
            if !isConfident { return understood == .done ? "упомянута — отметь, если сделана" : "\(understood.title)?" }
            return understood.title
        }
    }

    nonisolated struct ExtraLine: Sendable, Equatable, Identifiable {
        let id: Int
        var title: String
        var minutes: Int?
        var isIncluded: Bool
    }

    nonisolated struct MemoryLine: Sendable, Equatable, Identifiable {
        let id: Int
        var candidate: MemoryCandidate
        var isAccepted: Bool
    }

    let day: Date
    var transcript: String
    var source: CheckInSource
    var tasks: [TaskLine]
    var extra: [ExtraLine]
    var statedWorkMinutes: Int?
    var rating: DayRating?
    var energy: SelfReportedEnergy?
    var summary: String?
    var memory: [MemoryLine]
    /// Перенести незакрытые задачи дня на завтра.
    var movesUnfinishedToTomorrow: Bool
    let extractorID: String

    /// Строит черновик из разбора. На экране — задачи этого дня и всё, о чём
    /// человек говорил; сами отмечаются только уверенно понятые «сделал».
    static func make(from extraction: CheckInExtraction, request: CheckInRequest, source: CheckInSource) -> CheckInDraft {
        let time = request.time
        let lines = request.tasks.compactMap { task -> TaskLine? in
            let outcome = extraction.outcome(for: task.id)
            let planned = task.date.map { time.isSameDay($0, request.day) } ?? false
            guard planned || outcome != nil else { return nil }
            let confidentDone = outcome.map { $0.status == .done && $0.isConfident } ?? false
            return TaskLine(
                id: task.id,
                title: task.title,
                minutes: task.effectiveEstimatedMinutes,
                isPlannedForDay: planned,
                wasDone: task.isDone,
                understood: outcome?.status,
                isConfident: outcome?.isConfident ?? false,
                isDone: task.isDone || confidentDone
            )
        }

        return CheckInDraft(
            day: time.startOfDay(request.day),
            transcript: request.transcript,
            source: source,
            tasks: lines,
            extra: extraction.extra.enumerated().map { ExtraLine(id: $0.offset, title: $0.element.title, minutes: $0.element.minutes, isIncluded: true) },
            statedWorkMinutes: extraction.statedWorkMinutes,
            rating: extraction.rating,
            energy: extraction.energy,
            summary: extraction.summary,
            memory: extraction.memory.enumerated().map { MemoryLine(id: $0.offset, candidate: $0.element, isAccepted: true) },
            movesUnfinishedToTomorrow: true,
            extractorID: extraction.extractorID
        )
    }

    // MARK: Для экрана

    var doneCount: Int { tasks.filter(\.isDone).count }
    var plannedCount: Int { tasks.filter(\.isPlannedForDay).count }

    /// Объём работы: со слов человека или по оценкам отмеченных задач.
    var workMinutes: Int? {
        if let statedWorkMinutes { return statedWorkMinutes }
        let tasksMinutes = tasks.filter(\.isDone).reduce(0) { $0 + $1.minutes }
        let extraMinutes = extra.filter(\.isIncluded).compactMap(\.minutes).reduce(0, +)
        let total = tasksMinutes + extraMinutes
        return total > 0 ? total : nil
    }

    /// Какие задачи уедут на завтра, если переключатель включён.
    func unfinishedToMove(tasks all: [LineaTask], time: TimeContext) -> [LineaTask] {
        let open = Set(tasks.filter { $0.isPlannedForDay && !$0.isDone }.map(\.id))
        return all.filter { task in
            guard open.contains(task.id), !task.isDone else { return false }
            // Встречу, которая ещё впереди сегодня, не трогаем.
            if let start = task.scheduledStart, start > time.now { return false }
            return true
        }
    }
}
