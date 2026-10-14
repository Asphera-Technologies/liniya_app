//
//  TaskOwnership.swift
//  Linea
//
//  Чьё значение у параметра задачи — человека или Linea. Правило AI-разбора:
//  что человек задал сам, Linea сама не перезаписывает.
//
//    • Человек сохраняет задачу — карточкой, меню, свайпом, разбором «Без
//      даты», итогом дня: всё, что он поменял, становится его (`userEdited`).
//      Сказанное словами при создании — тоже его (`QuickTaskResolution`).
//    • Linea меняет задачу сама только через предложение (`TaskProposal`,
//      `applying`): берутся лишь параметры, которых человек не задавал.
//      Сейчас так обновляется одна сложность — после того как человек
//      переименовал задачу (`refreshedAfterEdit`). Разбор моделью, если он
//      появится, пойдёт тем же путём.
//    • Задача, сохранённая раньше, чем Linea стала это помнить, — вся
//      «человека»: что в ней трогали руками, неизвестно, и Linea не рискует.
//

import Foundation

/// Что Linea сама предлагает поставить задаче. `nil` — о параметре сказать
/// нечего: значение лучше оставить, чем придумать.
nonisolated struct TaskProposal: Hashable, Sendable {
    var date: Date?
    var deadline: Date?
    var scheduledStart: Date?
    var estimatedMinutes: Int?
    var priority: TaskPriority?
    var goalID: UUID?
    var demand: CognitiveDemand?

    init(
        date: Date? = nil,
        deadline: Date? = nil,
        scheduledStart: Date? = nil,
        estimatedMinutes: Int? = nil,
        priority: TaskPriority? = nil,
        goalID: UUID? = nil,
        demand: CognitiveDemand? = nil
    ) {
        self.date = date
        self.deadline = deadline
        self.scheduledStart = scheduledStart
        self.estimatedMinutes = estimatedMinutes
        self.priority = priority
        self.goalID = goalID
        self.demand = demand
    }
}

nonisolated enum TaskOwnership {

    /// Какие параметры отличаются у двух версий задачи.
    static func changedFields(from old: LineaTask, to new: LineaTask) -> Set<TaskField> {
        var fields: Set<TaskField> = []
        if old.date != new.date { fields.insert(.day) }
        if old.deadline != new.deadline { fields.insert(.deadline) }
        if old.scheduledStart != new.scheduledStart { fields.insert(.startTime) }
        if old.estimatedMinutes != new.estimatedMinutes { fields.insert(.duration) }
        if old.priority != new.priority { fields.insert(.priority) }
        if old.goalID != new.goalID { fields.insert(.goal) }
        if old.cognitiveDemand != new.cognitiveDemand { fields.insert(.demand) }
        return fields
    }

    /// Человек сохранил задачу: всё, что он поменял, становится его. Что он
    /// задал раньше, его и остаётся. Сам поменял день или время (карточкой,
    /// итогом дня, «Переносим») — место задачи снова выбирает он, а не Linea:
    /// «Пусть Linea решит» снято. Если же сохранение само выбрало, кто ставит
    /// задачу («Позже сегодня» в «Перенести»), так и остаётся.
    static func userEdited(previous: LineaTask, updated: LineaTask) -> LineaTask {
        var result = updated
        let changed = changedFields(from: previous, to: updated)
        // Поменянное — его; и то, что экран отметил как выбор человека, даже
        // если значение совпало («30 мин» тапом при оценке Linea 30 мин).
        result.userFields = previous.userFields.map { $0.union(changed).union(updated.userFields ?? []) }
        // Поменял длительность сам — она его (`estimated_duration_source = user`).
        if changed.contains(.duration) {
            result.estimatedDurationSource = updated.estimatedMinutes == nil ? nil : .user
        }
        if updated.rescheduleMode == previous.rescheduleMode, !changed.isDisjoint(with: [.day, .startTime]) {
            result.rescheduleMode = nil
        }
        return result
    }

    /// Linea ставит то, что предлагает, — только в параметры, которых человек
    /// не задавал. Возвращает и то, что поменялось.
    static func applying(_ proposal: TaskProposal, to task: LineaTask) -> (task: LineaTask, applied: Set<TaskField>) {
        var result = task
        var applied: Set<TaskField> = []
        if let date = proposal.date, !task.isSetByUser(.day), task.date != date {
            result.date = date
            applied.insert(.day)
        }
        if let deadline = proposal.deadline, !task.isSetByUser(.deadline), task.deadline != deadline {
            result.deadline = deadline
            applied.insert(.deadline)
        }
        if let start = proposal.scheduledStart, !task.isSetByUser(.startTime), task.scheduledStart != start {
            result.scheduledStart = start
            applied.insert(.startTime)
        }
        if let minutes = proposal.estimatedMinutes, !task.isSetByUser(.duration), task.estimatedMinutes != minutes {
            result.estimatedMinutes = minutes
            applied.insert(.duration)
        }
        if let priority = proposal.priority, !task.isSetByUser(.priority), task.priority != priority {
            result.priority = priority
            applied.insert(.priority)
        }
        if let goalID = proposal.goalID, !task.isSetByUser(.goal), task.goalID != goalID {
            result.goalID = goalID
            applied.insert(.goal)
        }
        if let demand = proposal.demand, !task.isSetByUser(.demand), task.cognitiveDemand != demand {
            result.cognitiveDemand = demand
            applied.insert(.demand)
        }
        return (result, applied)
    }

    /// Человек переименовал задачу — сложность и длительность, которые когда-то
    /// подставила Linea, следуют за новым названием так же, как при создании:
    /// «Позвонить Пете» → «Подготовить стратегию для Пети» — уже сложная и на
    /// полтора часа. Выбранное человеком Linea не трогает.
    static func refreshedAfterEdit(
        previous: LineaTask,
        updated: LineaTask,
        classifier: TaskClassifier = TaskClassifier()
    ) -> LineaTask {
        guard previous.title != updated.title else { return updated }
        let said = QuickTaskParser.demand(in: updated.title)
        let kind = classifier.classify(
            title: updated.title, goalID: updated.goalID, isFixed: updated.isFixed,
            demand: said, override: updated.kindOverride
        ).kind
        // Только оценку Linea: длительность задачи, сохранённой раньше, чем
        // Linea стала её оценивать, — человека.
        let minutes = updated.isDurationEstimatedByLinea
            ? DurationEstimator().rules(title: updated.title, kind: kind) : nil
        let applied = applying(TaskProposal(estimatedMinutes: minutes, demand: said ?? kind.typicalDemand), to: updated)
        var result = applied.task
        if applied.applied.contains(.duration) { result.estimatedDurationSource = .ai }
        return result
    }

    /// Сохранение человеком целиком — так задачу сохраняет `PlanStore`:
    /// поменянное — его, а сама Linea обновляет только своё.
    static func saved(previous: LineaTask, updated: LineaTask) -> LineaTask {
        refreshedAfterEdit(previous: previous, updated: userEdited(previous: previous, updated: updated))
    }
}
