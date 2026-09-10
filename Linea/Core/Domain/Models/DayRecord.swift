//
//  DayRecord.swift
//  Linea
//
//  Everything Linea knows about one day, stored as one document: the frozen
//  snapshot, the computed state, the plan (with its versions), scheduled
//  nudges and the user's feedback. Persisted as JSON blobs so the structure
//  can evolve without SwiftData migrations.
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
    var updatedAt: Date

    init(
        day: Date,
        snapshot: ContextSnapshot? = nil,
        state: UserState? = nil,
        plan: DayPlan? = nil,
        nudges: [Nudge] = [],
        feedback: [UserFeedback] = [],
        updatedAt: Date
    ) {
        self.day = day
        self.snapshot = snapshot
        self.state = state
        self.plan = plan
        self.nudges = nudges
        self.feedback = feedback
        self.updatedAt = updatedAt
    }

    var rating: DayRating? { feedback.compactMap(\.dayRating).last }
    var isPlanAccepted: Bool { plan?.status == .accepted }
}
