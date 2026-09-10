//
//  ContextSnapshot.swift
//  Linea
//
//  Everything the engines saw when they made a decision, frozen. Persisted
//  next to the plan so a plan, a nudge and the evening feedback all refer to
//  the same inputs, and so a day can be replayed in tests.
//

import Foundation

nonisolated struct ContextSnapshot: Codable, Sendable, Identifiable {
    static let schemaVersion = 1

    let id: UUID
    /// Start of the local day this snapshot describes.
    let day: Date
    let capturedAt: Date
    let timeZoneIdentifier: String

    /// Raw signals from every provider (history included), sorted deterministically.
    var signals: [ContextSignal]
    var providerStatuses: [ProviderID: ProviderStatus]

    // Typed slots — tasks and goals are the SUBJECT of decisions, not measurements.
    var tasks: [LineaTask]
    var goals: [LineaGoal]
    var commitments: [Commitment]
    var profile: UserProfile
    var nutrition: NutritionProfile?
    var meals: [MealLog]

    init(
        id: UUID,
        day: Date,
        capturedAt: Date,
        timeZoneIdentifier: String,
        signals: [ContextSignal],
        providerStatuses: [ProviderID: ProviderStatus],
        tasks: [LineaTask],
        goals: [LineaGoal],
        commitments: [Commitment],
        profile: UserProfile,
        nutrition: NutritionProfile? = nil,
        meals: [MealLog] = []
    ) {
        self.id = id
        self.day = day
        self.capturedAt = capturedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.signals = signals
        self.providerStatuses = providerStatuses
        self.tasks = tasks
        self.goals = goals
        self.commitments = commitments
        self.profile = profile
        self.nutrition = nutrition
        self.meals = meals
    }

    func signals(of kind: SignalKind) -> [ContextSignal] {
        signals.filter { $0.kind == kind }
    }

    func status(of provider: ProviderID) -> ProviderStatus? { providerStatuses[provider] }

    var activeGoals: [LineaGoal] { goals.filter { $0.isActive && !$0.isCompleted } }
}
