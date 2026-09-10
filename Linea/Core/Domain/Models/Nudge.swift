//
//  Nudge.swift
//  Linea
//
//  A moment-bound prompt («План немного отстаёт…»). Nudges are computed from
//  the accepted plan with their text and actions ready, so they can be
//  pre-scheduled as local notifications the moment the plan is accepted and
//  shown as a card when the app is open.
//

import Foundation

nonisolated enum NudgeKind: String, Codable, Hashable, Sendable {
    case behindSchedule
    case eveningCheckIn
    case morningBrief
    case preCommitment
}

nonisolated enum NudgeAction: Codable, Hashable, Sendable {
    case finishNow(taskID: UUID)
    case deferTask(taskID: UUID)
    case rateDay
    case openApp
    case dismiss

    var title: String {
        switch self {
        case .finishNow: return "Закрываем сейчас"
        case .deferTask: return "Переносим"
        case .rateDay: return "Оценить день"
        case .openApp: return "Открыть"
        case .dismiss: return "Позже"
        }
    }
}

nonisolated enum NudgeCancelCondition: Codable, Hashable, Sendable {
    case taskDone(UUID)
    case dayRated
    case planSuperseded
}

nonisolated struct Nudge: Codable, Hashable, Sendable, Identifiable {
    let id: String
    var kind: NudgeKind
    var fireAt: Date
    var taskID: UUID?
    var title: String
    var body: String
    var actions: [NudgeAction]
    var cancelWhen: [NudgeCancelCondition]
    var facts: [Fact]

    init(
        id: String,
        kind: NudgeKind,
        fireAt: Date,
        taskID: UUID? = nil,
        title: String,
        body: String,
        actions: [NudgeAction] = [],
        cancelWhen: [NudgeCancelCondition] = [],
        facts: [Fact] = []
    ) {
        self.id = id
        self.kind = kind
        self.fireAt = fireAt
        self.taskID = taskID
        self.title = title
        self.body = body
        self.actions = actions
        self.cancelWhen = cancelWhen
        self.facts = facts
    }
}

nonisolated enum NudgeResponse: String, Codable, Hashable, Sendable {
    case finishNow, deferred, dismissed, rated
}
