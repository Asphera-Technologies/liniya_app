//
//  PlanModels.swift
//  Linea
//
//  Domain models for Plan (tasks & goals). These are plain, persistence-
//  agnostic value types. The UI and repositories speak *these* types — never
//  SwiftData `@Model` objects directly — so a remote repository can later be
//  dropped in without touching feature UI.
//

import Foundation

/// Task importance. Kept intentionally small (normal / important) to match the
/// "Важно" tag in the approved Linea design.
enum TaskPriority: String, Codable, CaseIterable, Sendable {
    case normal
    case important

    var isImportant: Bool { self == .important }
}

/// A single task/plan item.
struct LineaTask: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var notes: String?
    /// The day the task is assigned to. `nil` means "Без дня".
    var date: Date?
    var priority: TaskPriority
    var isDone: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        date: Date? = nil,
        priority: TaskPriority = .normal,
        isDone: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.date = date
        self.priority = priority
        self.isDone = isDone
        self.createdAt = createdAt
    }
}

/// A personal goal with coarse progress.
struct LineaGoal: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    /// Progress from 0...1.
    var progress: Double
    var isCompleted: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        progress: Double = 0,
        isCompleted: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.progress = min(max(progress, 0), 1)
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }

    /// Quiet status line shown under the goal (e.g. "Выполнено", "50%").
    var statusText: String {
        if isCompleted { return "Выполнено" }
        return "\(Int((progress * 100).rounded()))%"
    }
}

/// A dated (or undated) group of tasks used to lay out the Plan screen,
/// e.g. "Сб · Сегодня" or "Без дня".
struct TaskSection: Identifiable {
    let id: String
    let day: Date?
    var tasks: [LineaTask]
}

/// The scope toggle on the Plan screen.
enum PlanScope: Int, CaseIterable {
    case week = 0
    case month = 1
}
