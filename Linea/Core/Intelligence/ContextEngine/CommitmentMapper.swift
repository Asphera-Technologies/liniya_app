//
//  CommitmentMapper.swift
//  Linea
//
//  Everything that occupies time becomes a `Commitment`, whoever reported it:
//  a meal window from the nutrition profile, a calendar event later, or a task
//  the user pinned to a time. The planner only ever sees this type, which is
//  why adding a calendar does not change the planner.
//

import Foundation

nonisolated struct CommitmentMapper: Sendable {
    init() {}

    /// Commitments for `day` from the collected signals and the day's tasks.
    /// Signals win over tasks when both describe the same task.
    func commitments(
        signals: [ContextSignal],
        tasks: [LineaTask],
        day: DateInterval,
        time: TimeContext
    ) -> [Commitment] {
        var result: [Commitment] = []
        var claimedTasks = Set<UUID>()

        for signal in signals where signal.kind == .commitment {
            guard signal.interval.intersects(day) || day.contains(signal.start) else { continue }
            guard signal.duration > 0 else { continue }
            let taskID = signal.attributes[SignalAttribute.taskID].flatMap(UUID.init(uuidString:))
            if let taskID { claimedTasks.insert(taskID) }
            result.append(
                Commitment(
                    id: signal.id,
                    title: signal.attributes[SignalAttribute.label] ?? "Занято",
                    start: signal.start,
                    end: signal.end,
                    kind: signal.attributes[SignalAttribute.commitmentKind]
                        .flatMap(CommitmentKind.init(rawValue:)) ?? .other,
                    source: signal.source,
                    taskID: taskID
                )
            )
        }

        // A task the user pinned to a time is a commitment: the planner must
        // not move it, and the nudge must count it as the next obligation.
        for task in tasks {
            guard let start = task.scheduledStart, !task.isDone, !claimedTasks.contains(task.id) else { continue }
            guard day.contains(start) else { continue }
            let end = start.addingTimeInterval(TimeInterval(task.effectiveEstimatedMinutes * 60))
            result.append(
                Commitment(
                    id: "task-\(task.id.uuidString)",
                    title: task.title,
                    start: start,
                    end: end,
                    kind: Self.kind(of: task),
                    source: .tasks,
                    taskID: task.id
                )
            )
        }

        return result.sorted { lhs, rhs in
            lhs.start != rhs.start ? lhs.start < rhs.start : lhs.id < rhs.id
        }
    }

    private static func kind(of task: LineaTask) -> CommitmentKind {
        CommitmentKind.inferred(fromTitle: task.title, default: .task)
    }
}
