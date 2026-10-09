//
//  DayRecord.swift
//  Linea
//
//  Everything Linea knows about one day, stored as one document: the frozen
//  snapshot, the computed state, the plan (with its versions), scheduled
//  nudges, the user's feedback and Linea's suggestions with the answers to
//  them. Persisted as JSON blobs so the structure can evolve without SwiftData
//  migrations — and read softly, so a record written before a field existed
//  is not lost.
//

import Foundation

nonisolated struct DayRecord: Codable, Sendable {
    static let schemaVersion = 1

    let day: Date
    var snapshot: ContextSnapshot?
    var state: UserState?
    var plan: DayPlan?
    var nudges: [Nudge]
    var feedback: [UserFeedback]
    /// Что Linea предлагала «сейчас» и что человек ответил (`SuggestionLog`).
    var suggestions: [TaskSuggestion]
    var updatedAt: Date

    init(
        day: Date,
        snapshot: ContextSnapshot? = nil,
        state: UserState? = nil,
        plan: DayPlan? = nil,
        nudges: [Nudge] = [],
        feedback: [UserFeedback] = [],
        suggestions: [TaskSuggestion] = [],
        updatedAt: Date
    ) {
        self.day = day
        self.snapshot = snapshot
        self.state = state
        self.plan = plan
        self.nudges = nudges
        self.feedback = feedback
        self.suggestions = suggestions
        self.updatedAt = updatedAt
    }

    /// Мягкое чтение: день, записанный до появления поля, читается целиком.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(Date.self, forKey: .day)
        snapshot = try container.decodeIfPresent(ContextSnapshot.self, forKey: .snapshot)
        state = try container.decodeIfPresent(UserState.self, forKey: .state)
        plan = try container.decodeIfPresent(DayPlan.self, forKey: .plan)
        nudges = try container.decodeIfPresent([Nudge].self, forKey: .nudges) ?? []
        feedback = try container.decodeIfPresent([UserFeedback].self, forKey: .feedback) ?? []
        suggestions = try container.decodeIfPresent([TaskSuggestion].self, forKey: .suggestions) ?? []
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    var rating: DayRating? { feedback.compactMap(\.dayRating).last }
    /// План против факта из итога дня, если человек его рассказал.
    var report: DayReportSummary? { feedback.compactMap(\.dayReport).last }
    /// На вечерний вопрос уже ответили — оценкой или итогом дня.
    var isReviewed: Bool { rating != nil || report != nil }
    var isPlanAccepted: Bool { plan?.status == .accepted }
}
