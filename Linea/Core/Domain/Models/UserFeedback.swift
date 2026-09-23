//
//  UserFeedback.swift
//  Linea
//
//  Everything the user tells Linea back: the evening rating, the day's report
//  from the check-in, plan acceptance, nudge responses, manual postponements. Stored with the state at that
//  moment so the Feedback Engine can relate «Тяжело» to what was predicted.
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
