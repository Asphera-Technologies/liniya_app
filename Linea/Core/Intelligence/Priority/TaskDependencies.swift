//
//  TaskDependencies.swift
//  Linea
//
//  «Сначала нужно»: какие задачи держат какие (`dependencies`). Граф строится
//  из `LineaTask.blockedBy` только по открытым задачам — закрытая или
//  удалённая задача уже никого не держит. Петля («A ждёт B, B ждёт A») не
//  ломает план: ребро, которое замкнуло бы её, не учитывается —
//  детерминированно, по порядку создания задач.
//

import Foundation

nonisolated struct TaskDependencies: Sendable {
    /// Задача → открытые задачи, которые её держат.
    private let blockers: [UUID: [UUID]]
    /// Задача → открытые задачи, которые её ждут, по порядку создания.
    private let waiting: [UUID: [UUID]]

    init(tasks: [LineaTask]) {
        let open = tasks.filter(\.isOpen)
        let openIDs = Set(open.map(\.id))
        var edges: [UUID: [UUID]] = [:]
        for task in open.sorted(by: DecisionEngine.chronological) {
            for blocker in task.blockedBy where blocker != task.id && openIDs.contains(blocker) {
                guard !Self.reaches(from: blocker, to: task.id, edges: edges) else { continue }
                edges[task.id, default: []].append(blocker)
            }
        }
        blockers = edges
        var waiting: [UUID: [UUID]] = [:]
        for task in open.sorted(by: DecisionEngine.chronological) {
            for blocker in edges[task.id] ?? [] { waiting[blocker, default: []].append(task.id) }
        }
        self.waiting = waiting
    }

    /// Открытые задачи, без которых `taskID` не начать. `done` — задачи,
    /// которые план уже поставил раньше и к этому моменту считает сделанными.
    func openBlockers(of taskID: UUID, assumingDone done: Set<UUID> = []) -> [UUID] {
        (blockers[taskID] ?? []).filter { !done.contains($0) }
    }

    /// Сколько открытых задач ждут эту.
    func dependents(of taskID: UUID) -> Int {
        waiting[taskID]?.count ?? 0
    }

    /// Открытые задачи, которые ждут эту, — давние первыми.
    func dependentIDs(of taskID: UUID) -> [UUID] {
        waiting[taskID] ?? []
    }

    /// Можно ли поставить `taskID` в зависимость от `blockerID`: не ждёт ли
    /// `blockerID` (через цепочку) саму `taskID` — иначе петля.
    static func canBlock(_ taskID: UUID, by blockerID: UUID, in tasks: [LineaTask]) -> Bool {
        guard taskID != blockerID else { return false }
        var edges: [UUID: [UUID]] = [:]
        for task in tasks where task.isOpen { edges[task.id] = task.blockedBy }
        return !reaches(from: blockerID, to: taskID, edges: edges)
    }

    /// Ждёт ли `start` задачу `target` — напрямую или через цепочку.
    private static func reaches(from start: UUID, to target: UUID, edges: [UUID: [UUID]]) -> Bool {
        var stack = [start]
        var seen = Set<UUID>()
        while let current = stack.popLast() {
            if current == target { return true }
            guard seen.insert(current).inserted else { continue }
            stack.append(contentsOf: edges[current] ?? [])
        }
        return false
    }
}

/// Сколько раз задачу переносили (`number_of_deferrals`).
nonisolated enum TaskDeferral {
    /// Задачу, которую пора было делать (сегодня или раньше), сдвинули на
    /// более поздний день или убрали у неё день. Так считаются «Переносим» в
    /// напоминании, перенос незакрытого итогом дня и перенос руками.
    static func isDeferral(from previous: LineaTask, to updated: LineaTask, time: TimeContext) -> Bool {
        guard !previous.isDone, !updated.isDone, let previousDay = previous.date else { return false }
        let was = time.startOfDay(previousDay)
        guard was <= time.today else { return false }
        guard let updatedDay = updated.date else { return true }
        return time.startOfDay(updatedDay) > was
    }

    /// Обновлённая задача со счётчиком переносов.
    static func counted(previous: LineaTask, updated: LineaTask, time: TimeContext) -> LineaTask {
        guard isDeferral(from: previous, to: updated, time: time) else { return updated }
        var result = updated
        result.deferralCount = max(previous.deferralCount, updated.deferralCount) + 1
        return result
    }
}
