//
//  GoalEntity.swift
//  Linea
//
//  SwiftData persistence model for goals. Implementation detail of the local
//  repository; mapping to/from the `LineaGoal` domain type lives here.
//  New fields are optional (lightweight migration); nil = pre-migration
//  defaults (week horizon, start = createdAt, active).
//

import Foundation
import SwiftData

@Model
final class GoalEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var progress: Double
    var isCompleted: Bool
    var createdAt: Date

    var horizonRaw: String?
    var startDate: Date?
    var isActive: Bool?

    init(
        id: UUID,
        title: String,
        progress: Double,
        isCompleted: Bool,
        createdAt: Date,
        horizonRaw: String? = nil,
        startDate: Date? = nil,
        isActive: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.progress = progress
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.horizonRaw = horizonRaw
        self.startDate = startDate
        self.isActive = isActive
    }
}

extension GoalEntity {
    convenience init(from goal: LineaGoal) {
        self.init(
            id: goal.id,
            title: goal.title,
            progress: goal.progress,
            isCompleted: goal.isCompleted,
            createdAt: goal.createdAt,
            horizonRaw: goal.horizon.rawValue,
            startDate: goal.startDate,
            isActive: goal.isActive
        )
    }

    var domain: LineaGoal {
        LineaGoal(
            id: id,
            title: title,
            progress: progress,
            isCompleted: isCompleted,
            createdAt: createdAt,
            horizon: horizonRaw.flatMap(GoalHorizon.init(rawValue:)) ?? .week,
            startDate: startDate ?? createdAt,
            isActive: isActive ?? true
        )
    }

    func apply(_ goal: LineaGoal) {
        title = goal.title
        progress = goal.progress
        isCompleted = goal.isCompleted
        horizonRaw = goal.horizon.rawValue
        startDate = goal.startDate
        isActive = goal.isActive
    }
}
