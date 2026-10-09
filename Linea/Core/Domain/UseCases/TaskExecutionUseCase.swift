//
//  TaskExecutionUseCase.swift
//  Linea
//
//  Одно действие человека с задачей — «Начать», «Завершить», «Не сейчас»,
//  убрать из планов, вернуть закрытую — целиком: задача меняется по правилу
//  `TaskLifecycle`, предложение Linea получает ответ (`SuggestionLog`), а в
//  день пишется отклик с тем, что было на самом деле. Так собираются данные
//  о реальном поведении: за что человек берётся, сколько это занимает, что
//  откладывает и от каких советов отказывается.
//
//  Чистая функция; сохраняют результат сторы (`IntelligenceStore`).
//

import Foundation

nonisolated struct TaskExecutionUseCase: Sendable {
    nonisolated enum Action: String, Sendable, Equatable {
        case start, finish, reopen, notNow, cancel
    }

    nonisolated struct Output: Sendable {
        let task: LineaTask
        /// Другие задачи, которые «Начать» сняло с работы: в работе одно дело.
        let paused: [LineaTask]
        /// День с откликом и ответом на предложение; nil — записи дня ещё нет.
        let record: DayRecord?

        init(task: LineaTask, paused: [LineaTask] = [], record: DayRecord?) {
            self.task = task
            self.paused = paused
            self.record = record
        }
    }

    private let lifecycle = TaskLifecycle()

    init() {}

    /// nil — такого перехода не бывает (начать сделанную, завершить
    /// отменённую): ни задача, ни день не меняются. `plannedMinutes` —
    /// сколько отводит план (для «Начать» — сколько отведено действию).
    /// `others` — остальные задачи: «Начать» снимает с работы начатые среди них.
    func run(
        _ action: Action,
        task: LineaTask,
        others: [LineaTask] = [],
        record: DayRecord?,
        plannedMinutes: Int,
        at moment: Date
    ) -> Output? {
        let open = record.flatMap { SuggestionLog.open(in: $0) }
        let offered = open?.taskID == task.id ? open : nil

        switch action {
        case .start:
            guard let updated = lifecycle.start(task, suggestionID: offered?.id, at: moment) else { return nil }
            let record = record.map { day -> DayRecord in
                var day = day
                if let open {
                    // Взялся за предложенное — принято; за другое — выбрал иное.
                    day = SuggestionLog.responding(offered == nil ? .otherChosen : .accepted,
                                                   to: open.taskID, in: day, at: moment).record
                }
                let start = ActionStart(taskID: task.id, minutes: plannedMinutes,
                                        wasAlternative: offered?.isAlternative ?? false, suggestionID: offered?.id)
                return appending(.actionStarted(start), to: day, at: moment)
            }
            let paused = others.filter { $0.id != task.id }.compactMap(lifecycle.pause)
            return Output(task: updated, paused: paused, record: record)

        case .finish:
            guard let updated = lifecycle.finish(task, suggestionID: offered?.id, at: moment) else { return nil }
            let record = record.map { day -> DayRecord in
                var day = day
                if offered != nil {
                    day = SuggestionLog.responding(.accepted, to: task.id, in: day, at: moment).record
                }
                let finish = TaskFinish(taskID: task.id, actualMinutes: updated.actualMinutes,
                                        plannedMinutes: plannedMinutes, suggestionID: updated.suggestionID)
                return appending(.taskFinished(finish), to: day, at: moment)
            }
            return Output(task: updated, record: record)

        case .reopen:
            guard let updated = lifecycle.reopen(task) else { return nil }
            // Закрыли по ошибке: прежняя отметка о завершении больше не правда.
            let record = record.map { appending(.taskReopened(taskID: task.id), to: $0, at: moment) }
            return Output(task: updated, record: record)

        case .notNow:
            guard let updated = lifecycle.notNow(task, at: moment) else { return nil }
            let record = record.map { day -> DayRecord in
                var day = day
                if offered != nil {
                    day = SuggestionLog.responding(.declined, to: task.id, in: day, at: moment).record
                }
                return appending(.taskNotNow(taskID: task.id, wasStarted: task.startedAt != nil), to: day, at: moment)
            }
            return Output(task: updated, record: record)

        case .cancel:
            guard let updated = lifecycle.cancel(task, at: moment) else { return nil }
            let record = record.map { day -> DayRecord in
                var day = day
                if offered != nil {
                    day = SuggestionLog.responding(.declined, to: task.id, in: day, at: moment).record
                }
                return appending(.taskCancelled(taskID: task.id), to: day, at: moment)
            }
            return Output(task: updated, record: record)
        }
    }

    /// Отклик в день вместе с тем, каким Linea видела человека в этот момент.
    private func appending(_ kind: FeedbackKind, to record: DayRecord, at moment: Date) -> DayRecord {
        var record = record
        record.feedback.append(UserFeedback(
            at: moment, kind: kind,
            energy: record.state?.energy, energyConfidence: record.state?.confidence,
            loadAdvice: record.state?.loadAdvice, planID: record.plan?.id
        ))
        record.updatedAt = moment
        return record
    }
}
