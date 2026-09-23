//
//  PlanStore.swift
//  Linea
//
//  The view-facing state for tasks & goals. It depends ONLY on the
//  `TaskRepository` / `GoalRepository` abstractions — never SwiftData — and
//  exposes plain domain values plus intent methods to the UI. After each
//  mutation it reloads from the repository (the source of truth), which keeps
//  Today and Plan in sync and stays correct once a remote/sync layer is added.
//

import Foundation
import Observation

@Observable
@MainActor
final class PlanStore {
    private let taskRepository: TaskRepository
    private let goalRepository: GoalRepository

    private(set) var tasks: [LineaTask] = []
    private(set) var goals: [LineaGoal] = []
    private(set) var errorMessage: String?

    /// A quiet warning shown on the Plan screen, e.g. when more than three
    /// goals are active. Advisory on purpose: the brief asks for 1-3 active
    /// goals, but blocking the user over it would be rude.
    private(set) var warningMessage: String?

    /// Called after every mutation so the day plan can be recomputed.
    /// Set by the composition root; nil in previews and tests.
    var onPlanInputsChanged: (@MainActor () async -> Void)?

    /// Plan screen scope + which week/month is being viewed.
    var scope: PlanScope = .week
    var referenceDate: Date = Date()

    init(taskRepository: TaskRepository, goalRepository: GoalRepository) {
        self.taskRepository = taskRepository
        self.goalRepository = goalRepository
    }

    // MARK: - Loading

    func load() async {
        do {
            tasks = try await taskRepository.all()
            goals = try await goalRepository.all()
            errorMessage = nil
            updateWarning()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateWarning() {
        let active = goals.filter { $0.isActive && !$0.isCompleted }.count
        warningMessage = active > LineaGoal.recommendedActiveLimit
            ? "Активных целей \(active). Linea лучше помогает, когда их не больше \(LineaGoal.recommendedActiveLimit)."
            : nil
    }

    // MARK: - Task intents

    /// Adds a new task or updates an existing one (matched by id).
    func saveTask(_ task: LineaTask) async {
        do {
            if tasks.contains(where: { $0.id == task.id }) {
                try await taskRepository.update(task)
            } else {
                try await taskRepository.add(task)
            }
            await load()
            await onPlanInputsChanged?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Several changes at once (the evening check-in closes and moves tasks):
    /// one reload and one replan instead of one per task.
    func saveTasks(_ updated: [LineaTask]) async {
        guard !updated.isEmpty else { return }
        do {
            for task in updated {
                if tasks.contains(where: { $0.id == task.id }) {
                    try await taskRepository.update(task)
                } else {
                    try await taskRepository.add(task)
                }
            }
            await load()
            await onPlanInputsChanged?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Marks a task done/undone. `completedAt` is what lets the plan know the
    /// day is on track, so it is stamped here rather than in the UI.
    func toggleTask(_ task: LineaTask) async {
        var updated = task
        updated.isDone.toggle()
        updated.completedAt = updated.isDone ? Date() : nil
        await saveTask(updated)
    }

    /// The "переносим" answer to a nudge: move the task to another day and
    /// let the plan rebuild without it.
    func deferTask(_ task: LineaTask, to day: Date) async {
        var updated = task
        updated.date = Calendar.current.startOfDay(for: day)
        updated.scheduledStart = nil
        await saveTask(updated)
    }

    func deleteTask(_ task: LineaTask) async {
        do {
            try await taskRepository.delete(id: task.id)
            await load()
            await onPlanInputsChanged?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Goal intents

    func saveGoal(_ goal: LineaGoal) async {
        do {
            if goals.contains(where: { $0.id == goal.id }) {
                try await goalRepository.update(goal)
            } else {
                try await goalRepository.add(goal)
            }
            await load()
            await onPlanInputsChanged?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteGoal(_ goal: LineaGoal) async {
        do {
            try await goalRepository.delete(id: goal.id)
            await load()
            await onPlanInputsChanged?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Goals the Decision Engine may align tasks with.
    var activeGoals: [LineaGoal] {
        goals.filter { $0.isActive && !$0.isCompleted }
    }

    /// Progress derived from linked tasks when there are any, so a goal moves
    /// on its own; the manual slider stays the source otherwise.
    func derivedProgress(for goal: LineaGoal) -> Double? {
        let linked = tasks.filter { $0.goalID == goal.id }
        guard !linked.isEmpty else { return nil }
        return Double(linked.filter(\.isDone).count) / Double(linked.count)
    }

    // MARK: - Derived: Today

    /// The single most important open task to surface on Today. Prefers tasks
    /// due today, then important ones, then the oldest. Returns nil if none.
    var topTaskToday: LineaTask? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return tasks
            .filter { !$0.isDone }
            .sorted { lhs, rhs in
                let lToday = lhs.date.map { calendar.isDate($0, inSameDayAs: today) } ?? false
                let rToday = rhs.date.map { calendar.isDate($0, inSameDayAs: today) } ?? false
                if lToday != rToday { return lToday }
                if lhs.priority.isImportant != rhs.priority.isImportant {
                    return lhs.priority.isImportant
                }
                return lhs.createdAt < rhs.createdAt
            }
            .first
    }

    // MARK: - Derived: Plan sections

    /// The date interval currently displayed, based on scope + referenceDate.
    var visibleInterval: DateInterval {
        let calendar = Calendar.current
        let component: Calendar.Component = scope == .week ? .weekOfYear : .month
        return calendar.dateInterval(of: component, for: referenceDate)
            ?? DateInterval(start: referenceDate, duration: 0)
    }

    /// A human label for the visible interval (e.g. "31 августа — 6 сентября").
    var intervalLabel: String {
        let interval = visibleInterval
        switch scope {
        case .week:
            let last = Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            return "\(Self.dayMonth.string(from: interval.start)) — \(Self.dayMonth.string(from: last))"
        case .month:
            return Self.monthYear.string(from: interval.start).capitalizedFirstLetter
        }
    }

    func goToPrevious() {
        shift(by: -1)
    }

    func goToNext() {
        shift(by: 1)
    }

    private func shift(by amount: Int) {
        let calendar = Calendar.current
        let component: Calendar.Component = scope == .week ? .weekOfYear : .month
        if let moved = calendar.date(byAdding: component, value: amount, to: referenceDate) {
            referenceDate = moved
        }
    }

    /// Tasks grouped for display: dated tasks that fall inside the visible
    /// interval (grouped by day), followed by an always-visible "Без дня"
    /// group for undated tasks.
    var taskSections: [TaskSection] {
        let calendar = Calendar.current
        let interval = visibleInterval

        let dated = tasks.filter { task in
            guard let date = task.date else { return false }
            return interval.contains(date) || calendar.isDate(date, inSameDayAs: interval.start)
        }
        let undated = tasks.filter { $0.date == nil }

        let byDay = Dictionary(grouping: dated) { calendar.startOfDay(for: $0.date!) }

        var sections: [TaskSection] = byDay.keys.sorted().map { day in
            TaskSection(
                id: Self.dayHeader(for: day),
                day: day,
                tasks: byDay[day]!.sorted(by: Self.taskOrder)
            )
        }

        if !undated.isEmpty {
            sections.append(
                TaskSection(id: "Без дня", day: nil, tasks: undated.sorted(by: Self.taskOrder))
            )
        }
        return sections
    }

    // MARK: - Ordering & formatting helpers

    private static func taskOrder(_ lhs: LineaTask, _ rhs: LineaTask) -> Bool {
        if lhs.isDone != rhs.isDone { return !lhs.isDone }
        if lhs.priority.isImportant != rhs.priority.isImportant {
            return lhs.priority.isImportant
        }
        return lhs.createdAt < rhs.createdAt
    }

    private static func dayHeader(for day: Date) -> String {
        let calendar = Calendar.current
        let weekday = shortWeekday.string(from: day).capitalizedFirstLetter
        if calendar.isDateInToday(day) { return "\(weekday) · Сегодня" }
        if calendar.isDateInTomorrow(day) { return "\(weekday) · Завтра" }
        return "\(weekday) · \(dayMonth.string(from: day))"
    }

    private static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM"
        return f
    }()

    private static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    private static let shortWeekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEEEEE"
        return f
    }()
}

private extension String {
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
