//
//  LocalTaskRepository.swift
//  Linea
//
//  Local, on-device `TaskRepository` backed by SwiftData. Implementation
//  detail of the Data layer; the protocol lives in Core/Domain/Protocols.
//

import Foundation
import SwiftData

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
