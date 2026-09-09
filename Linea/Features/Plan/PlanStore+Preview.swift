//
//  PlanStore+Preview.swift
//  Linea
//
//  Preview-only factory. Kept separate so `PlanStore` itself stays free of any
//  SwiftData import, reinforcing that the store depends only on the repository
//  abstractions.
//

import SwiftData

extension PlanStore {
    /// An in-memory PlanStore for SwiftUI previews (no disk writes).
    @MainActor
    static var preview: PlanStore {
        let container = try! ModelContainer(
            for: TaskEntity.self, GoalEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return PlanStore(
            taskRepository: LocalTaskRepository(context: container.mainContext),
            goalRepository: LocalGoalRepository(context: container.mainContext)
        )
    }
}
