//
//  GoalEntity.swift
//  Linea
//
//  SwiftData persistence model for goals. Implementation detail of the local
//  repository; mapping to/from the `LineaGoal` domain type lives here.
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

    init(
        id: UUID,
        title: String,
        progress: Double,
        isCompleted: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.progress = progress
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
}

extension GoalEntity {
    convenience init(from goal: LineaGoal) {
        self.init(
            id: goal.id,
            title: goal.title,
            progress: goal.progress,
            isCompleted: goal.isCompleted,
            createdAt: goal.createdAt
        )
    }

    var domain: LineaGoal {
        LineaGoal(
            id: id,
            title: title,
            progress: progress,
            isCompleted: isCompleted,
            createdAt: createdAt
        )
    }

    func apply(_ goal: LineaGoal) {
        title = goal.title
        progress = goal.progress
        isCompleted = goal.isCompleted
    }
}
