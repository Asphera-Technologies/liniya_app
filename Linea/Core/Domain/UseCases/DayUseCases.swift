//
//  DayUseCases.swift
//  Linea
//
//  The rest of the day after the morning plan: accepting it, checking whether
//  it is slipping, answering a nudge, and rating the day. Each is a pure
//  function over data the store already loaded, so the whole wow-scenario can
//  be replayed in a test without a device.
//

import Foundation

// MARK: - Accept

/// «Принять план». Freezes the proposal and prepares the day's nudges with
/// their text already written — the notification that fires at 14:30 cannot
/// compute anything, so everything it needs is decided here.
nonisolated struct AcceptPlanUseCase: Sendable {
    let nudgeEngine: NudgeEngine
    let config: EngineConfig

    init(nudgeEngine: NudgeEngine, config: EngineConfig = .default) {
        self.nudgeEngine = nudgeEngine
        self.config = config
    }

    nonisolated struct Output: Sendable {
        let record: DayRecord
        /// Nudges to hand to the notification scheduler.
        let nudges: [Nudge]
    }

    func run(record: DayRecord, calibration: Calibration, time: TimeContext) -> Output {
        guard var plan = record.plan, let snapshot = record.snapshot, let state = record.state else {
            return Output(record: record, nudges: [])
        }
        plan.status = .accepted
        plan.acceptedAt = time.now

        var record = record
        record.plan = plan
        record.feedback.append(
            UserFeedback(
                at: time.now, kind: .planAccepted(planID: plan.id),
                energy: state.energy, energyConfidence: state.confidence,
                loadAdvice: state.loadAdvice, planID: plan.id
            )
        )
        let nudges = nudgeEngine.nudges(
            NudgeContext(
                plan: plan, snapshot: snapshot, state: state,
                feedback: record.feedback, existing: [],
                calibration: calibration, config: config, time: time
            )
        )
        record.nudges = nudges
        record.updatedAt = time.now
        return Output(record: record, nudges: nudges)
    }
}

// MARK: - Check in

/// «План отстаёт?» — evaluated whenever the app comes to the foreground and
/// when a notification arrives. Tasks are passed in fresh because the user may
/// have closed one since the snapshot was taken.
nonisolated struct CheckInUseCase: Sendable {
    let nudgeEngine: NudgeEngine
    let config: EngineConfig

    init(nudgeEngine: NudgeEngine, config: EngineConfig = .default) {
        self.nudgeEngine = nudgeEngine
        self.config = config
    }

    nonisolated struct Output: Sendable {
        /// The nudge to show right now, if any.
        let due: Nudge?
        /// The full list for the notification scheduler to re-sync.
        let scheduled: [Nudge]
    }

    func run(record: DayRecord, tasks: [LineaTask], calibration: Calibration, time: TimeContext) -> Output {
        guard let plan = record.plan, plan.status == .accepted,
              var snapshot = record.snapshot, let state = record.state else {
            return Output(due: nil, scheduled: [])
        }
        snapshot.tasks = tasks
        let context = NudgeContext(
            plan: plan, snapshot: snapshot, state: state,
            feedback: record.feedback, existing: [],
            calibration: calibration, config: config, time: time
        )
        return Output(due: nudgeEngine.due(context).first, scheduled: nudgeEngine.nudges(context))
    }
}

// MARK: - Respond

/// The answer to a nudge. The use case records what happened and says what the
/// app must do next; it never touches the task itself, because tasks belong to
/// the user and are edited through `PlanStore`.
nonisolated struct RespondToNudgeUseCase: Sendable {
    init() {}

    nonisolated enum Effect: Sendable, Equatable {
        /// Rebuild the rest of the day (the user starts the task now).
        case replan
        /// Move the task to another day, then rebuild.
        case deferTask(taskID: UUID, to: Date)
        /// Ask for the evening rating.
        case rateDay
        case none
    }

    nonisolated struct Output: Sendable {
        let record: DayRecord
        let effect: Effect
    }

    func run(record: DayRecord, nudge: Nudge, action: NudgeAction, time: TimeContext) -> Output {
        var record = record
        let response: NudgeResponse
        var effect: Effect = .none

        switch action {
        case .finishNow(let taskID):
            response = .finishNow
            record.feedback.append(feedback(.taskStartedNow(taskID: taskID), record: record, time: time))
            effect = .replan
        case .deferTask(let taskID):
            response = .deferred
            let tomorrow = time.adding(days: 1, to: time.today)
            record.feedback.append(feedback(.taskPostponed(taskID: taskID, fromDay: time.today), record: record, time: time))
            effect = .deferTask(taskID: taskID, to: tomorrow)
        case .rateDay:
            response = .rated
            effect = .rateDay
        case .openApp, .dismiss:
            response = .dismissed
        }

        record.feedback.append(feedback(.nudgeResponse(nudgeID: nudge.id, response: response), record: record, time: time))
        record.nudges.removeAll { $0.id == nudge.id }
        record.updatedAt = time.now
        return Output(record: record, effect: effect)
    }

    private func feedback(_ kind: FeedbackKind, record: DayRecord, time: TimeContext) -> UserFeedback {
        UserFeedback(
            at: time.now, kind: kind,
            energy: record.state?.energy, energyConfidence: record.state?.confidence,
            loadAdvice: record.state?.loadAdvice, planID: record.plan?.id
        )
    }
}

// MARK: - Rate the day

/// «Как прошёл день?» — the only thing that teaches Linea anything. The
/// calibration is recomputed from the whole history, so rating the same day
/// twice cannot drift the model.
nonisolated struct RecordDayRatingUseCase: Sendable {
    let feedbackEngine: FeedbackEngine

    init(feedbackEngine: FeedbackEngine = FeedbackEngine()) {
        self.feedbackEngine = feedbackEngine
    }

    nonisolated struct Output: Sendable {
        let record: DayRecord
        let calibration: Calibration
    }

    func run(record: DayRecord, rating: DayRating, history: [DayRecord], previous: Calibration, time: TimeContext) -> Output {
        var record = record
        // One rating per day: a second answer replaces the first.
        record.feedback.removeAll { $0.dayRating != nil }
        record.feedback.append(
            UserFeedback(
                at: time.now, kind: .dayRating(rating),
                energy: record.state?.energy, energyConfidence: record.state?.confidence,
                loadAdvice: record.state?.loadAdvice, planID: record.plan?.id
            )
        )
        record.nudges.removeAll { $0.kind == .eveningCheckIn }
        record.updatedAt = time.now

        var updatedHistory = history.filter { $0.day != record.day }
        updatedHistory.append(record)
        let calibration = feedbackEngine.calibrate(history: updatedHistory, previous: previous, time: time)
        return Output(record: record, calibration: calibration)
    }
}
