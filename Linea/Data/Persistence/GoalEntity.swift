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

    /// Больше не используется: раньше цель имела горизонт «неделя/месяц».
    /// Колонка оставлена, чтобы обновление не стирало существующие цели — по
    /// ней вычисляется срок для тех, что были созданы до появления `endDate`.
    var horizonRaw: String?
    var startDate: Date?
    var endDate: Date?
    var isActive: Bool?

    init(
        id: UUID,
        title: String,
        progress: Double,
        isCompleted: Bool,
        createdAt: Date,
        horizonRaw: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        isActive: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.progress = progress
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.horizonRaw = horizonRaw
        self.startDate = startDate
        self.endDate = endDate
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
            startDate: goal.startDate,
            endDate: goal.endDate,
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
            startDate: startDate ?? createdAt,
            endDate: endDate ?? Self.migratedEndDate(horizonRaw: horizonRaw, startDate: startDate ?? createdAt),
            isActive: isActive ?? true
        )
    }

    func apply(_ goal: LineaGoal) {
        title = goal.title
        progress = goal.progress
        isCompleted = goal.isCompleted
        startDate = goal.startDate
        endDate = goal.endDate
        isActive = goal.isActive
    }

    /// Цель, созданная до появления явного срока, получает его из старого
    /// горизонта: конец той же недели или того же месяца.
    private static func migratedEndDate(horizonRaw: String?, startDate: Date) -> Date? {
        guard let horizonRaw else { return nil }
        let calendar = Calendar.current
        let component: Calendar.Component = horizonRaw == "week" ? .weekOfYear : .month
        let start = calendar.startOfDay(for: startDate)
        guard let next = calendar.date(byAdding: component, value: 1, to: start) else { return nil }
        return calendar.date(byAdding: .day, value: -1, to: next)
    }
}
