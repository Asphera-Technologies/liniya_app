//
//  DayPlan.swift
//  Linea
//
//  The Decision Engine's answer to «what should the user do next?» for one
//  day: ordered, time-boxed blocks plus structured recommendations. A plan is
//  a SEPARATE entity — accepting or revising it never mutates tasks, so the
//  history of «plan vs. fact» stays clean for the Feedback Engine.
//

import Foundation

nonisolated enum PlanStatus: String, Codable, Hashable, Sendable {
    case proposed, accepted, superseded
}

nonisolated enum PlanBlockKind: String, Codable, Hashable, Sendable {
    /// Work on a task chosen by the planner.
    case focus
    /// A commitment (meeting, fixed task, workout) that blocks time.
    case commitment
    case meal
    case rest
}

/// Per-component scores that produced a block's total — kept for
/// explainability and for future calibration, never recomputed from text.
nonisolated struct ScoreBreakdown: Codable, Hashable, Sendable {
    var urgency: Double
    var importance: Double
    var goalAlignment: Double
    var energyFit: Double?
    var durationFit: Double
    var total: Double

    init(urgency: Double, importance: Double, goalAlignment: Double, energyFit: Double?, durationFit: Double, total: Double) {
        self.urgency = urgency
        self.importance = importance
        self.goalAlignment = goalAlignment
        self.energyFit = energyFit
        self.durationFit = durationFit
        self.total = total
    }
}

nonisolated struct PlanBlock: Codable, Hashable, Sendable, Identifiable {
    let id: String
    var kind: PlanBlockKind
    var taskID: UUID?
    var title: String
    var start: Date
    var end: Date
    var score: ScoreBreakdown?
    /// Among the day's top actions («3 приоритетных действия»).
    var isTop: Bool
    /// Placed by the user (manual move) — the planner keeps it on replan.
    var isPinned: Bool
    var facts: [Fact]

    init(
        id: String,
        kind: PlanBlockKind,
        taskID: UUID? = nil,
        title: String,
        start: Date,
        end: Date,
        score: ScoreBreakdown? = nil,
        isTop: Bool = false,
        isPinned: Bool = false,
        facts: [Fact] = []
    ) {
        self.id = id
        self.kind = kind
        self.taskID = taskID
        self.title = title
        self.start = start
        self.end = max(start, end)
        self.score = score
        self.isTop = isTop
        self.isPinned = isPinned
        self.facts = facts
    }

    var interval: DateInterval { DateInterval(start: start, end: end) }
    var durationMinutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

nonisolated enum RecommendationKind: String, Codable, Hashable, Sendable {
    /// The morning brief («Доброе утро…»).
    case dayBrief
    /// «Сегодня нагрузку лучше немного снизить.»
    case loadAdjustment
    /// A task pushed out of today.
    case deferTask
    case meal
    case preWorkoutMeal
    case hydration
    case custom
}

nonisolated enum RecommendationAction: Codable, Hashable, Sendable {
    case acceptPlan
    case openTask(UUID)
    case deferTask(UUID)
    case markMealEaten(MealKind)
    case dismiss
}

/// Structured advice produced by rules. `message` is always rule-based text;
/// `explanation` is an optional LLM rephrasing validated against `facts`.
nonisolated struct Recommendation: Codable, Hashable, Sendable, Identifiable {
    let id: String
    var kind: RecommendationKind
    var title: String?
    var message: String
    var explanation: String?
    var facts: [Fact]
    var relatedTaskID: UUID?
    var actions: [RecommendationAction]
    /// Higher first when several compete for the Today screen.
    var priority: Int

    init(
        id: String,
        kind: RecommendationKind,
        title: String? = nil,
        message: String,
        explanation: String? = nil,
        facts: [Fact] = [],
        relatedTaskID: UUID? = nil,
        actions: [RecommendationAction] = [],
        priority: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
        self.explanation = explanation
        self.facts = facts
        self.relatedTaskID = relatedTaskID
        self.actions = actions
        self.priority = priority
    }
}

nonisolated struct DayPlan: Codable, Sendable, Identifiable {
    static let schemaVersion = 1

    let id: UUID
    let day: Date
    var version: Int
    var status: PlanStatus
    let createdAt: Date
    var acceptedAt: Date?
    let snapshotID: UUID
    var blocks: [PlanBlock]
    var topTaskIDs: [UUID]
    var deferredTaskIDs: [UUID]
    var recommendations: [Recommendation]
    /// Facts about the plan as a whole (top count, hard-work deadline…).
    var facts: [Fact]
    /// Which explainer wrote `recommendations[].explanation` (diagnostics).
    var explainerID: String?

    init(
        id: UUID,
        day: Date,
        version: Int = 1,
        status: PlanStatus = .proposed,
        createdAt: Date,
        acceptedAt: Date? = nil,
        snapshotID: UUID,
        blocks: [PlanBlock],
        topTaskIDs: [UUID],
        deferredTaskIDs: [UUID] = [],
        recommendations: [Recommendation] = [],
        facts: [Fact] = [],
        explainerID: String? = nil
    ) {
        self.id = id
        self.day = day
        self.version = version
        self.status = status
        self.createdAt = createdAt
        self.acceptedAt = acceptedAt
        self.snapshotID = snapshotID
        self.blocks = blocks
        self.topTaskIDs = topTaskIDs
        self.deferredTaskIDs = deferredTaskIDs
        self.recommendations = recommendations
        self.facts = facts
        self.explainerID = explainerID
    }

    var focusBlocks: [PlanBlock] { blocks.filter { $0.kind == .focus } }

    func block(for taskID: UUID) -> PlanBlock? {
        blocks.first { $0.taskID == taskID }
    }

    var brief: Recommendation? { recommendations.first { $0.kind == .dayBrief } }
}
