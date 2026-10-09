//
//  UserFeedback.swift
//  Linea
//
//  Everything the user tells Linea back: the evening rating, the day's report
//  from the check-in, plan acceptance, nudge responses, manual postponements,
//  and how tasks were actually done — started, finished with the real
//  duration, «Не сейчас», cancelled. Stored with the state at that moment so
//  the Feedback Engine can relate «Тяжело» to what was predicted.
//

import Foundation

nonisolated enum FeedbackKind: Codable, Hashable, Sendable {
    case dayRating(DayRating)
    case planAccepted(planID: UUID)
    case nudgeResponse(nudgeID: String, response: NudgeResponse)
    case taskPostponed(taskID: UUID, fromDay: Date)
    case taskStartedNow(taskID: UUID)
    case mealLogged(MealKind)
    /// Итог дня: сколько плана случилось на самом деле (см. `CheckInEntry`).
    case dayReport(DayReportSummary)
    /// «Начать» на действии «Сейчас» (см. `NextAction`) — или на задаче в
    /// списке и в карточке.
    case actionStarted(ActionStart)
    /// «Завершить» (или «Готово»): сколько заняло на самом деле.
    case taskFinished(TaskFinish)
    /// «Не сейчас»: задача была начата или только предложена.
    case taskNotNow(taskID: UUID, wasStarted: Bool)
    /// Задачу убрали из планов.
    case taskCancelled(taskID: UUID)
    /// Закрытую задачу вернули: прежнее `taskFinished` больше не правда.
    /// Журнал только дописывается — так его не сломает пересчёт дня, идущий
    /// одновременно с ответом человека.
    case taskReopened(taskID: UUID)
}

/// Задача сделана: сколько было отведено и сколько ушло на самом деле.
nonisolated struct TaskFinish: Codable, Hashable, Sendable {
    let taskID: UUID
    /// От «Начать» до «Завершить»; `nil` — не начинали или забыли завершить.
    let actualMinutes: Int?
    /// Сколько отводил план (оценка с калибровкой).
    let plannedMinutes: Int
    /// Предложение Linea, через которое задачу взяли или закрыли.
    let suggestionID: UUID?
}

nonisolated struct UserFeedback: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let at: Date
    let kind: FeedbackKind
    /// Predicted energy / confidence at the time (for calibration).
    let energy: Double?
    let energyConfidence: Double?
    let loadAdvice: LoadAdvice?
    let planID: UUID?

    init(
        id: UUID = UUID(),
        at: Date,
        kind: FeedbackKind,
        energy: Double? = nil,
        energyConfidence: Double? = nil,
        loadAdvice: LoadAdvice? = nil,
        planID: UUID? = nil
    ) {
        self.id = id
        self.at = at
        self.kind = kind
        self.energy = energy
        self.energyConfidence = energyConfidence
        self.loadAdvice = loadAdvice
        self.planID = planID
    }

    var dayRating: DayRating? {
        if case .dayRating(let r) = kind { return r }
        return nil
    }

    var dayReport: DayReportSummary? {
        if case .dayReport(let report) = kind { return report }
        return nil
    }
}
