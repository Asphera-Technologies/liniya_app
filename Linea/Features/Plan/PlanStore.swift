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
//  What happens to a task when the person works on it — «Начать»,
//  «Завершить», «Не сейчас», «Удалить» — goes through `IntelligenceStore`
//  (`TaskExecutionUseCase`): it also records the day's feedback and the answer
//  to Linea's suggestion, then saves the task here.
//

import Foundation
import Observation

@Observable
@MainActor
final class PlanStore {
    private let taskRepository: TaskRepository
    private let goalRepository: GoalRepository

    /// Задачи человека. Убранных из планов («Удалить», `cancelledAt`) здесь
    /// нет: для экранов и движков их нет, но в хранилище они остаются —
    /// отменённое тоже поведение.
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

    private let timeProvider: @MainActor () -> TimeContext

    init(
        taskRepository: TaskRepository,
        goalRepository: GoalRepository,
        time: @escaping @MainActor () -> TimeContext = { .live }
    ) {
        self.taskRepository = taskRepository
        self.goalRepository = goalRepository
        self.timeProvider = time
    }

    // MARK: - Loading

    func load() async {
        do {
            tasks = try await taskRepository.all().filter { $0.cancelledAt == nil }
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

    /// Adds a new task or updates an existing one (matched by id). A task that
    /// was due and moves later is counted as deferred — the priority engine
    /// lifts a task that keeps slipping (`TaskDeferral`). Everything saved here
    /// is the person's own doing: what they changed becomes theirs, and Linea
    /// never overwrites it by itself (`TaskOwnership`).
    func saveTask(_ task: LineaTask) async {
        do {
            if let previous = tasks.first(where: { $0.id == task.id }) {
                try await taskRepository.update(edited(previous: previous, updated: task, time: timeProvider()))
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
        let time = timeProvider()
        do {
            for task in updated {
                if let previous = tasks.first(where: { $0.id == task.id }) {
                    try await taskRepository.update(edited(previous: previous, updated: task, time: time))
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

    /// Правка человека: поменянное — его, сложность, которую подставляла
    /// Linea, следует за новым названием, перенос засчитывается.
    private func edited(previous: LineaTask, updated: LineaTask, time: TimeContext) -> LineaTask {
        TaskDeferral.counted(previous: previous, updated: TaskOwnership.saved(previous: previous, updated: updated), time: time)
    }

    /// The "переносим" answer to a nudge: move the task to another day and
    /// let the plan rebuild without it.
    func deferTask(_ task: LineaTask, to day: Date) async {
        var updated = task
        updated.date = Calendar.current.startOfDay(for: day)
        updated.scheduledStart = nil
        await saveTask(updated)
    }

    /// Изменения, где ядро уже решило, чьё что: «Пусть Linea решит» отдаёт
    /// день и время Linea (`AutoReschedule`), и она же переставляет задачу,
    /// чей день прошёл. Поэтому без пометок «поменял человек» — только
    /// перенос засчитывается. `replans: false` — пересчёт дня уже идёт.
    func saveDecided(_ updated: [LineaTask], replans: Bool = true) async {
        guard !updated.isEmpty else { return }
        let time = timeProvider()
        do {
            for task in updated {
                let previous = tasks.first { $0.id == task.id }
                try await taskRepository.update(previous.map { TaskDeferral.counted(previous: $0, updated: task, time: time) } ?? task)
            }
            await load()
            if replans { await onPlanInputsChanged?() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// «Вернуть» сразу после «Неактуально»: убранная из планов задача снова в
    /// них. Её нет в `tasks` (убранные не показываются), поэтому — обновление
    /// по id, а не добавление.
    func restoreTask(_ task: LineaTask) async {
        do {
            try await taskRepository.update(task)
            await load()
            await onPlanInputsChanged?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// «Привязать к цели» из меню строки; `nil` — без цели.
    func linkTask(_ task: LineaTask, toGoal goalID: UUID?) async {
        guard task.goalID != goalID else { return }
        var updated = task
        updated.goalID = goalID
        await saveTask(updated)
    }

    /// «Изменить приоритет» из меню строки.
    func setPriority(_ priority: TaskPriority, of task: LineaTask) async {
        guard task.priority != priority else { return }
        var updated = task
        updated.priority = priority
        await saveTask(updated)
    }

    // MARK: - Goal intents

    /// Сохранение цели — всегда дело человека, значит, он её пересмотрел:
    /// время пересмотра — сейчас, а что он сдвинул вперёд (этап, число,
    /// стадию), попадает в журнал продвижений (`GoalRevision`).
    func saveGoal(_ goal: LineaGoal) async {
        do {
            let previous = goals.first { $0.id == goal.id }
            let saved = GoalRevision.saved(previous: previous, updated: goal, time: timeProvider())
            if previous != nil {
                try await goalRepository.update(saved)
            } else {
                try await goalRepository.add(saved)
            }
            await load()
            await onPlanInputsChanged?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// «Пока нет» на «Хочешь найти для неё небольшое окно завтра?»: Linea
    /// отступает. Это ответ на вопрос, а не пересмотр цели — время пересмотра
    /// не меняется, план не пересобирается.
    func snoozeAttention(of goalID: UUID, until moment: Date) async {
        guard var goal = goals.first(where: { $0.id == goalID }) else { return }
        goal.attentionSnoozedUntil = moment
        do {
            try await goalRepository.update(goal)
            await load()
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

    /// Прогресс цели — по её методу (`GoalProgressEngine`). Закрытые задачи
    /// цели процент не двигают: они — значимые действия и последнее
    /// продвижение. Один расчёт для строки в «Плане» и карточки цели.
    func progress(for goal: LineaGoal) -> GoalProgress {
        GoalProgressEngine().progress(of: goal, tasks: tasks, time: timeProvider())
    }

    var time: TimeContext { timeProvider() }

    /// «На этой неделе»: сколько продвижений по каждой цели и одно
    /// наблюдение — для недели, которую показывает «План». Встречи — из
    /// календаря за эту неделю. В режиме «Месяц» и для недель впереди — нет.
    func weeklyReview(meetings: [Commitment]) -> WeeklyReview? {
        guard scope == .week else { return nil }
        return WeeklyReviewBuilder().review(week: visibleInterval, goals: goals, tasks: tasks,
                                            meetings: meetings, time: timeProvider())
    }

    // MARK: - Derived: Today

    /// The single most important open task to surface on Today. Prefers tasks
    /// due today, then important ones, then the oldest. Returns nil if none.
    var topTaskToday: LineaTask? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return tasks
            // «Без даты» — не главное сегодня: у таких задач дня нет.
            .filter { !$0.isDone && !InboxReview.isInInbox($0) }
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
    /// interval (grouped by day), then «Со сроком» — no day but a deadline,
    /// soonest first. «Без даты» (the inbox) is its own list, `inboxTasks`.
    var taskSections: [TaskSection] {
        let calendar = Calendar.current
        let interval = visibleInterval

        let dated = tasks.filter { task in
            guard let date = task.date else { return false }
            return interval.contains(date) || calendar.isDate(date, inSameDayAs: interval.start)
        }
        let dueOnly = tasks.filter { task in
            guard task.date == nil, task.deadline != nil else { return false }
            return !task.isDone || (task.completedAt.map(interval.contains) ?? false)
        }

        let byDay = Dictionary(grouping: dated) { calendar.startOfDay(for: $0.date!) }

        var sections: [TaskSection] = byDay.keys.sorted().map { day in
            TaskSection(
                id: Self.dayHeader(for: day),
                day: day,
                tasks: byDay[day]!.sorted(by: Self.taskOrder)
            )
        }

        if !dueOnly.isEmpty {
            let ordered = dueOnly.sorted { lhs, rhs in
                if lhs.isDone != rhs.isDone { return !lhs.isDone }
                return (lhs.deadline ?? .distantFuture) < (rhs.deadline ?? .distantFuture)
            }
            sections.append(TaskSection(id: "Со сроком", day: nil, tasks: ordered))
        }
        return sections
    }

    /// «Без даты» — входящие: открытые задачи без дня и срока, давние первыми,
    /// плюс закрытые в видимый период, чтобы отметка не исчезала сразу.
    var inboxTasks: [LineaTask] {
        let interval = visibleInterval
        let closed = tasks.filter { task in
            task.isDone && task.date == nil && task.deadline == nil && task.scheduledStart == nil
                && (task.completedAt.map(interval.contains) ?? false)
        }
        return InboxReview.inbox(tasks) + closed.sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
    }

    /// Разбор «Без даты»: задача получает день или срок — или остаётся без
    /// даты, но больше не считается неразобранной.
    func sortInboxTask(_ task: LineaTask, as choice: InboxReview.Choice, profile: UserProfile) async {
        await saveTask(InboxReview().apply(choice, to: task, profile: profile, time: timeProvider()))
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
