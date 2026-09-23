//
//  SubmitCheckInUseCase.swift
//  Linea
//
//  «Сохранить» на экране проверки итога дня. Одна чистая функция делает всё,
//  что следует из подтверждённого рассказа:
//    • закрывает отмеченные задачи и переносит незакрытые на завтра;
//    • пишет запись в дневник с короткой выжимкой;
//    • пополняет память фактами, которые человек оставил отмеченными;
//    • кладёт в день «план против факта» и оценку, пересчитывает калибровку.
//
//  Сама она ничего не сохраняет: возвращает новые значения, а store решает,
//  куда их записать. Поэтому весь вечерний сценарий проверяется тестом.
//

import Foundation

nonisolated struct SubmitCheckInUseCase: Sendable {
    let consolidator: MemoryConsolidator
    let digestBuilder: DayDigestBuilder
    let feedbackEngine: FeedbackEngine

    init(
        consolidator: MemoryConsolidator = MemoryConsolidator(),
        digestBuilder: DayDigestBuilder = DayDigestBuilder(),
        feedbackEngine: FeedbackEngine = FeedbackEngine()
    ) {
        self.consolidator = consolidator
        self.digestBuilder = digestBuilder
        self.feedbackEngine = feedbackEngine
    }

    nonisolated struct Input: Sendable {
        let draft: CheckInDraft
        /// Все задачи пользователя в текущем виде.
        let tasks: [LineaTask]
        /// Запись дня, о котором рассказ, если день уже планировался.
        let record: DayRecord?
        /// Дни за последний месяц — для пересчёта калибровки.
        let history: [DayRecord]
        let calibration: Calibration
        let memory: UserMemory
        /// Прежний итог этого дня: повторный рассказ его заменяет.
        let previous: CheckInEntry?
        let time: TimeContext
    }

    nonisolated struct Output: Sendable {
        let entry: CheckInEntry
        /// Задачи, которые изменились: закрытые и перенесённые.
        let changedTasks: [LineaTask]
        let movedTaskIDs: [UUID]
        let memory: UserMemory
        let addedFacts: [MemoryFact]
        let record: DayRecord
        let calibration: Calibration
    }

    func run(_ input: Input) -> Output {
        let time = input.time
        let draft = input.draft
        let day = time.startOfDay(draft.day)
        let byID = Dictionary(input.tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Рассказ после полуночи — про вчера: задача закрыта тем днём.
        let closedAt = min(time.now, time.dayInterval(containing: day).end.addingTimeInterval(-60))

        // 1. Задачи, которые человек отметил.
        var changed: [UUID: LineaTask] = [:]
        for line in draft.tasks where line.isDone && !line.wasDone {
            guard var task = byID[line.id], !task.isDone else { continue }
            task.isDone = true
            task.completedAt = closedAt
            changed[task.id] = task
        }

        // 2. Незакрытое — на завтра, если человек не выключил перенос.
        var moved: [UUID] = []
        if draft.movesUnfinishedToTomorrow {
            let tomorrow = time.adding(days: 1, to: day)
            let current = input.tasks.map { changed[$0.id] ?? $0 }
            for var task in draft.unfinishedToMove(tasks: current, time: time) {
                task.date = tomorrow
                task.scheduledStart = nil
                changed[task.id] = task
                moved.append(task.id)
            }
        }

        // 3. Итог и запись дневника.
        let report = CheckInReport(
            completed: draft.tasks.filter(\.isDone).map {
                ReportedTask(taskID: $0.id, title: $0.title, minutes: $0.minutes, status: .done)
            },
            unfinished: draft.tasks.filter { !$0.isDone && ($0.isPlannedForDay || $0.understood != nil) }.map {
                ReportedTask(taskID: $0.id, title: $0.title, minutes: $0.minutes,
                             status: $0.understood == .partial ? .partial : .notDone)
            },
            extra: draft.extra.filter(\.isIncluded).map { ExtraWork(title: $0.title, minutes: $0.minutes) },
            statedWorkMinutes: draft.statedWorkMinutes,
            rating: draft.rating,
            energy: draft.energy,
            summary: draft.summary,
            plannedCount: draft.plannedCount,
            completedPlannedCount: draft.tasks.filter { $0.isPlannedForDay && $0.isDone }.count,
            movedToTomorrow: moved
        )
        let entry = CheckInEntry(
            id: input.previous?.id ?? DeterministicID.uuid(from: "checkin|\(DeterministicID.dayKey(day, time: time))"),
            day: day,
            createdAt: input.previous?.createdAt ?? time.now,
            updatedAt: time.now,
            source: draft.source,
            transcript: draft.transcript.trimmingCharacters(in: .whitespacesAndNewlines),
            report: report,
            digest: digestBuilder.digest(for: report, day: day, time: time),
            extractorID: draft.extractorID
        )

        // 4. Память — только то, что человек оставил отмеченным.
        let accepted = draft.memory.filter(\.isAccepted).map(\.candidate)
        let merged = consolidator.merge(accepted, into: input.memory, source: .checkIn(day: day), time: time)

        // 5. День: план против факта, оценка, вечерний вопрос снят.
        var record = input.record ?? DayRecord(day: day, updatedAt: time.now)
        let done = Set(draft.tasks.filter(\.isDone).map(\.id))
        record.feedback.removeAll { $0.dayReport != nil }
        record.feedback.append(
            UserFeedback(
                at: time.now,
                kind: .dayReport(summary(of: report, plan: record.plan, done: done, lines: draft.tasks)),
                energy: record.state?.energy, energyConfidence: record.state?.confidence,
                loadAdvice: record.state?.loadAdvice, planID: record.plan?.id
            )
        )
        if let rating = draft.rating {
            // Одна оценка на день: итог дня заменяет нажатую раньше кнопку.
            record.feedback.removeAll { $0.dayRating != nil }
            record.feedback.append(
                UserFeedback(
                    at: time.now, kind: .dayRating(rating),
                    energy: record.state?.energy, energyConfidence: record.state?.confidence,
                    loadAdvice: record.state?.loadAdvice, planID: record.plan?.id
                )
            )
        }
        record.nudges.removeAll { $0.kind == .eveningCheckIn }
        record.updatedAt = time.now

        var history = input.history.filter { $0.day != record.day }
        history.append(record)
        let calibration = feedbackEngine.calibrate(history: history, previous: input.calibration, time: time)

        return Output(
            entry: entry,
            changedTasks: input.tasks.compactMap { changed[$0.id] },
            movedTaskIDs: moved,
            memory: merged.memory,
            addedFacts: merged.added,
            record: record,
            calibration: calibration
        )
    }

    /// План против факта. Если день планировался, считаем по рабочим блокам
    /// плана — ровно то, что Linea предлагала; иначе по задачам дня.
    func summary(of report: CheckInReport, plan: DayPlan?, done: Set<UUID>, lines: [CheckInDraft.TaskLine]) -> DayReportSummary {
        let blocks = (plan?.focusBlocks ?? []).filter { $0.taskID != nil }
        if !blocks.isEmpty {
            let plannedIDs = Set(blocks.compactMap(\.taskID))
            let closedBlocks = blocks.filter { block in block.taskID.map(done.contains) ?? false }
            return DayReportSummary(
                plannedTasks: plannedIDs.count,
                completedPlannedTasks: plannedIDs.filter(done.contains).count,
                plannedMinutes: blocks.reduce(0) { $0 + $1.durationMinutes },
                completedPlannedMinutes: closedBlocks.reduce(0) { $0 + $1.durationMinutes },
                workMinutes: report.workMinutes
            )
        }
        let planned = lines.filter(\.isPlannedForDay)
        return DayReportSummary(
            plannedTasks: planned.count,
            completedPlannedTasks: planned.filter(\.isDone).count,
            plannedMinutes: planned.reduce(0) { $0 + $1.minutes },
            completedPlannedMinutes: planned.filter(\.isDone).reduce(0) { $0 + $1.minutes },
            workMinutes: report.workMinutes
        )
    }
}
