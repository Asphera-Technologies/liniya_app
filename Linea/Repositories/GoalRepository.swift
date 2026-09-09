//
//  GoalRepository.swift
//  Linea
//
//  The goal persistence boundary. Same design as `TaskRepository`: async
//  protocol the UI depends on, with a SwiftData-backed local implementation.
//  A `RemoteGoalRepository` can adopt this later without UI changes.
//

import Foundation
import SwiftData

protocol GoalRepository {
    func all() async throws -> [LineaGoal]
    func add(_ goal: LineaGoal) async throws
    func update(_ goal: LineaGoal) async throws
    func delete(id: UUID) async throws
}

/// Local, on-device implementation backed by SwiftData.
@MainActor
final class LocalGoalRepository: GoalRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func all() async throws -> [LineaGoal] {
        let descriptor = FetchDescriptor<GoalEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor).map(\.domain)
    }

    func add(_ goal: LineaGoal) async throws {
        context.insert(GoalEntity(from: goal))
        try context.save()
    }

    func update(_ goal: LineaGoal) async throws {
        let id = goal.id
        let descriptor = FetchDescriptor<GoalEntity>(
            predicate: #Predicate { $0.id == id }
        )
        guard let entity = try context.fetch(descriptor).first else { return }
        entity.apply(goal)
        try context.save()
    }

    func delete(id: UUID) async throws {
        let descriptor = FetchDescriptor<GoalEntity>(
            predicate: #Predicate { $0.id == id }
        )
        guard let entity = try context.fetch(descriptor).first else { return }
        context.delete(entity)
        try context.save()
    }
}
