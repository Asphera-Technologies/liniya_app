//
//  PlanModels.swift
//  Linea
//
//  Domain models for Plan (tasks & goals). These are plain, persistence-
//  agnostic value types. The UI and repositories speak *these* types — never
//  SwiftData `@Model` objects directly — so a remote repository can later be
//  dropped in without touching feature UI.
//
//  Time semantics of a task (deliberately three different things):
//    • `date`           — the DAY the user planned to do it (nil = «Без дня»);
//    • `deadline`       — the moment it must be done by (drives urgency);
//    • `scheduledStart` — a fixed start the user chose («Тренировка 17:00»);
//                         such a task is a commitment, the planner won't move it.
//  Where the planner PUTS a task lives in `DayPlan`, never in the task.
//

import Foundation

/// Приоритет задачи: низкий, средний, высокий.
///
/// Сырые значения (`low`/`normal`/`important`) намеренно оставлены прежними —
/// по ним читаются уже сохранённые задачи. Пользователь видит только `title`.
nonisolated enum TaskPriority: String, Codable, CaseIterable, Sendable {
    case low
    case normal
    case important

    var isImportant: Bool { self == .important }

    var title: String {
        switch self {
        case .low: return "Низкий"
        case .normal: return "Средний"
        case .important: return "Высокий"
        }
    }

    /// Importance component for scoring, 0…1.
    var score: Double {
        switch self {
        case .low: return 0.2
        case .normal: return 0.5
        case .important: return 1.0
        }
    }
}

/// How much focused mental effort a task needs — the input to `energyFit`.
nonisolated enum CognitiveDemand: String, Codable, CaseIterable, Sendable {
    case light
    case normal
    case deep

    /// Demand on a 0…1 scale (brief: письма 0.3 / презентация 0.9).
    var score: Double {
        switch self {
        case .light: return 0.3
        case .normal: return 0.6
        case .deep: return 0.9
        }
    }

    var title: String {
        switch self {
        case .light: return "Лёгкая"
        case .normal: return "Обычная"
        case .deep: return "Сложная"
        }
    }
}

/// A single task/plan item.
nonisolated struct LineaTask: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var title: String
    var notes: String?
    /// The day the task is assigned to. `nil` means "Без дня".
    var date: Date?
    var priority: TaskPriority
    var isDone: Bool
    var createdAt: Date

    // Intelligence inputs (all optional / defaulted → additive persistence change)
    var deadline: Date?
    var scheduledStart: Date?
    var estimatedMinutes: Int?
    var cognitiveDemand: CognitiveDemand
    var goalID: UUID?
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        date: Date? = nil,
        priority: TaskPriority = .normal,
        isDone: Bool = false,
        createdAt: Date = Date(),
        deadline: Date? = nil,
        scheduledStart: Date? = nil,
        estimatedMinutes: Int? = nil,
        cognitiveDemand: CognitiveDemand = .normal,
        goalID: UUID? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.date = date
        self.priority = priority
        self.isDone = isDone
        self.createdAt = createdAt
        self.deadline = deadline
        self.scheduledStart = scheduledStart
        self.estimatedMinutes = estimatedMinutes
        self.cognitiveDemand = cognitiveDemand
        self.goalID = goalID
        self.completedAt = completedAt
    }

    /// Duration the planner works with when the user gave none.
    static let defaultEstimatedMinutes = 45

    var effectiveEstimatedMinutes: Int { max(5, estimatedMinutes ?? LineaTask.defaultEstimatedMinutes) }

    /// A task with a user-chosen start is a commitment for the planner.
    var isFixed: Bool { scheduledStart != nil }
}

/// A personal goal with coarse progress.
nonisolated struct LineaGoal: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var title: String
    /// Progress from 0...1.
    var progress: Double
    var isCompleted: Bool
    var createdAt: Date

    // Intelligence inputs
    /// Start of the goal period; defaults to the creation day.
    var startDate: Date
    /// Когда цель должна быть достигнута. `nil` — срок не задан: цель просто
    /// активна, и связанные с ней задачи получают ровный приоритет.
    var endDate: Date?
    var isActive: Bool

    init(
        id: UUID = UUID(),
        title: String,
        progress: Double = 0,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        startDate: Date? = nil,
        endDate: Date? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.title = title
        self.progress = min(max(progress, 0), 1)
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.startDate = startDate ?? createdAt
        self.endDate = endDate
        self.isActive = isActive
    }

    /// Сколько дней осталось до срока; `nil`, если срок не задан.
    func daysLeft(from moment: Date, calendar: Calendar) -> Int? {
        guard let endDate else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: moment),
                                           to: calendar.startOfDay(for: endDate)).day ?? 0
        return max(0, days)
    }

    /// Срок прошёл, а цель не закрыта.
    func isOverdue(at moment: Date, calendar: Calendar) -> Bool {
        guard let endDate, !isCompleted else { return false }
        return calendar.startOfDay(for: endDate) < calendar.startOfDay(for: moment)
    }

    /// Soft limit from the brief: 1–3 active goals.
    static let recommendedActiveLimit = 3

    /// Quiet status line shown under the goal (e.g. "Выполнено", "50%").
    var statusText: String {
        if isCompleted { return "Выполнено" }
        return "\(Int((progress * 100).rounded()))%"
    }
}

/// A dated (or undated) group of tasks used to lay out the Plan screen,
/// e.g. "Сб · Сегодня" or "Без дня".
nonisolated struct TaskSection: Identifiable, Sendable {
    let id: String
    let day: Date?
    var tasks: [LineaTask]
}

/// The scope toggle on the Plan screen.
nonisolated enum PlanScope: Int, CaseIterable, Sendable {
    case week = 0
    case month = 1
}
