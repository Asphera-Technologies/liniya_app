//
//  TaskEntity.swift
//  Linea
//
//  SwiftData persistence model for tasks. This is an implementation detail of
//  the local repository — it must not leak into feature UI. Mapping to/from
//  the `LineaTask` domain type lives here.
//

import Foundation
import SwiftData

@Model
final class TaskEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String?
    var dueDate: Date?
    var priorityRaw: String
    var isDone: Bool
    var createdAt: Date

    init(
        id: UUID,
        title: String,
        notes: String?,
        dueDate: Date?,
        priorityRaw: String,
        isDone: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.priorityRaw = priorityRaw
        self.isDone = isDone
        self.createdAt = createdAt
    }
}

extension TaskEntity {
    convenience init(from task: LineaTask) {
        self.init(
            id: task.id,
            title: task.title,
            notes: task.notes,
            dueDate: task.date,
            priorityRaw: task.priority.rawValue,
            isDone: task.isDone,
            createdAt: task.createdAt
        )
    }

    /// Maps this persistence object into the domain type.
    var domain: LineaTask {
        LineaTask(
            id: id,
            title: title,
            notes: notes,
            date: dueDate,
            priority: TaskPriority(rawValue: priorityRaw) ?? .normal,
            isDone: isDone,
            createdAt: createdAt
        )
    }

    /// Applies mutable fields from a domain task (id/createdAt are immutable).
    func apply(_ task: LineaTask) {
        title = task.title
        notes = task.notes
        dueDate = task.date
        priorityRaw = task.priority.rawValue
        isDone = task.isDone
    }
}
