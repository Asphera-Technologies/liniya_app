//
//  TaskRepository.swift
//  Linea
//
//  The task persistence boundary. Feature UI depends on this protocol, not on
//  SwiftData. The methods are async so a future `RemoteTaskRepository` (and a
//  `SyncService` coordinating local + remote) can adopt the same interface
//  without any change to the Plan UI.
//

import Foundation
import SwiftData

protocol TaskRepository {
    func all() async throws -> [LineaTask]
    func add(_ task: LineaTask) async throws
    func update(_ task: LineaTask) async throws
    func delete(id: UUID) async throws
}

/// Local, on-device implementation backed by SwiftData.
@MainActor
final class LocalTaskRepository: TaskRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func all() async throws -> [LineaTask] {
        let descriptor = FetchDescriptor<TaskEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor).map(\.domain)
    }

    func add(_ task: LineaTask) async throws {
        context.insert(TaskEntity(from: task))
        try context.save()
    }

    func update(_ task: LineaTask) async throws {
        let id = task.id
        let descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate { $0.id == id }
        )
        guard let entity = try context.fetch(descriptor).first else { return }
        entity.apply(task)
        try context.save()
    }

    func delete(id: UUID) async throws {
        let descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate { $0.id == id }
        )
        guard let entity = try context.fetch(descriptor).first else { return }
        context.delete(entity)
        try context.save()
    }
}
