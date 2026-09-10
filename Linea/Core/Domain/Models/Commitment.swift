//
//  Commitment.swift
//  Linea
//
//  A block of time the user cannot use for planned work: a meeting, a meal
//  window, a planned workout, or a task with a fixed start. Commitments come
//  from ANY connector via `.commitment` signals (calendar, nutrition, tasks);
//  the planner only ever sees this type.
//

import Foundation

nonisolated enum CommitmentKind: String, Codable, Hashable, Sendable {
    case meeting, meal, workout, task, other

    /// Linea has no separate «событие» entity in v1, so a training session is
    /// recognised by its name — whether it came from a task the user pinned to
    /// a time or from a calendar event. Shared so both sides agree.
    static func inferred(fromTitle title: String, default fallback: CommitmentKind) -> CommitmentKind {
        title.lowercased().contains("тренировк") ? .workout : fallback
    }
}

nonisolated struct Commitment: Codable, Hashable, Sendable, Identifiable {
    let id: String
    var title: String
    var start: Date
    var end: Date
    var kind: CommitmentKind
    var source: ProviderID
    /// The task this commitment represents, if it is a task with a fixed start.
    var taskID: UUID?

    init(id: String, title: String, start: Date, end: Date, kind: CommitmentKind, source: ProviderID, taskID: UUID? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = max(start, end)
        self.kind = kind
        self.source = source
        self.taskID = taskID
    }

    var interval: DateInterval { DateInterval(start: start, end: end) }
    var durationMinutes: Int { Int(end.timeIntervalSince(start) / 60) }
}
