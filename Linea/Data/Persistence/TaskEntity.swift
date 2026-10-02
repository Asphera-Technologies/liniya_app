//
//  TaskEntity.swift
//  Linea
//
//  SwiftData persistence model for tasks. This is an implementation detail of
//  the local repository — it must not leak into feature UI. Mapping to/from
//  the `LineaTask` domain type lives here.
//
//  Intelligence fields were added as OPTIONAL properties so SwiftData performs
//  a lightweight migration on devices that already have data.
//

import Foundation
import SwiftData

@Model
final class TaskEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String?
    var dueDate: Date?          // = LineaTask.date (the planned DAY); name kept for migration
    var priorityRaw: String
    var isDone: Bool
    var createdAt: Date

    // Intelligence inputs (all optional → lightweight migration)
    var deadline: Date?
    var scheduledStart: Date?
    var estimatedMinutes: Int?
    var cognitiveDemandRaw: String?
    var goalID: UUID?
    var completedAt: Date?
    /// Тип задачи, выбранный человеком; nil — тип определяет Linea.
    var kindRaw: String?
    /// Сколько раз задачу переносили; nil у задач, сохранённых раньше.
    var deferralCount: Int?
    /// «Сначала нужно»: id задач через запятую. Строкой, а не массивом, —
    /// самая простая для lightweight-миграции колонка.
    var blockedByRaw: String?
    /// Разобрана из «Без даты» и оставлена там; nil — не разбиралась.
    var inboxReviewedAt: Date?

    init(
        id: UUID,
        title: String,
        notes: String?,
        dueDate: Date?,
        priorityRaw: String,
        isDone: Bool,
        createdAt: Date,
        deadline: Date? = nil,
        scheduledStart: Date? = nil,
        estimatedMinutes: Int? = nil,
        cognitiveDemandRaw: String? = nil,
        goalID: UUID? = nil,
        completedAt: Date? = nil,
        kindRaw: String? = nil,
        deferralCount: Int? = nil,
        blockedByRaw: String? = nil,
        inboxReviewedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.priorityRaw = priorityRaw
        self.isDone = isDone
        self.createdAt = createdAt
        self.deadline = deadline
        self.scheduledStart = scheduledStart
        self.estimatedMinutes = estimatedMinutes
        self.cognitiveDemandRaw = cognitiveDemandRaw
        self.goalID = goalID
        self.completedAt = completedAt
        self.kindRaw = kindRaw
        self.deferralCount = deferralCount
        self.blockedByRaw = blockedByRaw
        self.inboxReviewedAt = inboxReviewedAt
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
            createdAt: task.createdAt,
            deadline: task.deadline,
            scheduledStart: task.scheduledStart,
            estimatedMinutes: task.estimatedMinutes,
            cognitiveDemandRaw: task.cognitiveDemand.rawValue,
            goalID: task.goalID,
            completedAt: task.completedAt,
            kindRaw: task.kindOverride?.rawValue,
            deferralCount: task.deferralCount,
            blockedByRaw: Self.raw(task.blockedBy),
            inboxReviewedAt: task.inboxReviewedAt
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
            createdAt: createdAt,
            deadline: deadline,
            scheduledStart: scheduledStart,
            estimatedMinutes: estimatedMinutes,
            cognitiveDemand: cognitiveDemandRaw.flatMap(CognitiveDemand.init(rawValue:)) ?? .normal,
            goalID: goalID,
            completedAt: completedAt,
            kindOverride: kindRaw.flatMap(TaskKind.init(rawValue:)),
            deferralCount: deferralCount ?? 0,
            blockedBy: Self.ids(blockedByRaw),
            inboxReviewedAt: inboxReviewedAt
        )
    }

    /// Applies mutable fields from a domain task (id/createdAt are immutable).
    func apply(_ task: LineaTask) {
        title = task.title
        notes = task.notes
        dueDate = task.date
        priorityRaw = task.priority.rawValue
        isDone = task.isDone
        deadline = task.deadline
        scheduledStart = task.scheduledStart
        estimatedMinutes = task.estimatedMinutes
        cognitiveDemandRaw = task.cognitiveDemand.rawValue
        goalID = task.goalID
        completedAt = task.completedAt
        kindRaw = task.kindOverride?.rawValue
        deferralCount = task.deferralCount
        blockedByRaw = Self.raw(task.blockedBy)
        inboxReviewedAt = task.inboxReviewedAt
    }

    private static func raw(_ ids: [UUID]) -> String? {
        ids.isEmpty ? nil : ids.map(\.uuidString).joined(separator: ",")
    }

    private static func ids(_ raw: String?) -> [UUID] {
        (raw ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }
}
