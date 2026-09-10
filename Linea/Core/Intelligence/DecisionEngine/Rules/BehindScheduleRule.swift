//
//  BehindScheduleRule.swift
//  Linea
//
//  «План немного отстаёт. До следующего обязательства осталось 1 ч 20 мин.» —
//  the nudge of the wow-scenario. It exists to ask ONE useful question at ONE
//  useful moment, so almost all of the code below is about not asking it:
//  outside the workday, in quiet hours, twice for the same task, or when there
//  is no longer enough room before the next commitment to act on the answer.
//

import Foundation

nonisolated struct BehindScheduleRule: RendererAwareNudgeRule {
    let id = "behindSchedule"
    let renderer: (any TextRenderer)?

    init(renderer: (any TextRenderer)? = nil) {
        self.renderer = renderer
    }

    func bound(to renderer: any TextRenderer) -> any NudgeRule {
        BehindScheduleRule(renderer: renderer)
    }

    func nudges(_ context: NudgeContext) -> [Nudge] {
        guard let renderer else { return [] }
        let time = context.time
        let now = time.now
        let plan = context.plan
        let profile = context.snapshot.profile
        let day = time.startOfDay(plan.day)
        let workdayEnd = time.date(on: day, at: profile.workdayEnd)
        let grace = TimeInterval(context.calibration.nudgeGraceMinutes * 60)
        let taskByID = Dictionary(context.snapshot.tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let alreadyNudged = Set(context.existing.compactMap(\.taskID))

        var result: [Nudge] = []
        var takenMoments: Set<Date> = Set(context.existing.map(\.fireAt))

        // `plan.topTaskIDs` is already the day's ranking: the first task that
        // claims a moment keeps it.
        for taskID in plan.topTaskIDs {
            guard let task = taskByID[taskID], !task.isDone, !alreadyNudged.contains(taskID) else { continue }
            guard let block = plan.blocks.first(where: { $0.kind == .focus && $0.taskID == taskID }) else { continue }

            var fireAt = max(block.end.addingTimeInterval(grace), now)
            // A nudge whose moment has already passed is asked right now; only a
            // future one is moved off time the user cannot interrupt.
            if fireAt > now, let busy = busyInterval(containing: fireAt, excluding: block.id, context: context) {
                fireAt = busy.end.addingTimeInterval(grace)
            }
            guard fireAt < workdayEnd else { continue }
            guard !profile.isQuiet(time.timeOfDay(of: fireAt)) else { continue }

            var facts: [Fact] = [.behindSchedule(
                taskID: taskID, title: task.title,
                lagMinutes: max(0, Int(fireAt.timeIntervalSince(block.end) / 60))
            )]
            let minutesLeft: Int
            if let next = nextCommitment(after: fireAt, context: context) {
                minutesLeft = Int(next.start.timeIntervalSince(fireAt) / 60)
                facts.append(.nextCommitment(title: next.title, at: next.start, minutesLeft: minutesLeft))
            } else {
                minutesLeft = Int(workdayEnd.timeIntervalSince(fireAt) / 60)
                facts.append(.endOfWorkday(minutesLeft: minutesLeft))
            }
            // Too little room left to do anything with the answer.
            guard minutesLeft >= context.config.nudgeMinimumWindowMinutes else { continue }
            guard takenMoments.insert(fireAt).inserted else { continue }

            let planned = PlanDuration.minutes(for: task, calibration: context.calibration)
            let actions: [NudgeAction] = Double(minutesLeft) >= 0.8 * Double(planned)
                ? [.finishNow(taskID: taskID), .deferTask(taskID: taskID)]
                : [.deferTask(taskID: taskID)]

            let explanation = renderer.render(ExplanationRequest(
                moment: .nudge,
                facts: facts,
                taskTitles: [task.title],
                localeIdentifier: time.locale.identifier,
                hour: time.timeOfDay(of: fireAt).hour,
                userName: profile.name,
                timeZoneIdentifier: time.timeZone.identifier
            ))

            result.append(Nudge(
                id: NudgeIdentity.behindSchedule(day: day, taskID: taskID, time: time),
                kind: .behindSchedule, fireAt: fireAt, taskID: taskID,
                title: explanation.headline, body: explanation.body,
                actions: actions, cancelWhen: [.taskDone(taskID)], facts: facts
            ))
        }

        return result.sorted { $0.fireAt == $1.fireAt ? $0.id < $1.id : $0.fireAt < $1.fireAt }
    }

    // MARK: - Helpers

    /// Time the user is already inside: any block of the plan except the one the
    /// nudge is about, plus commitments the plan does not carry.
    private func busyInterval(containing moment: Date, excluding blockID: String, context: NudgeContext) -> DateInterval? {
        var intervals = context.plan.blocks.filter { $0.id != blockID }.map(\.interval)
        intervals += context.snapshot.commitments.map(\.interval)
        return StateMath.union(intervals)
            .first { $0.start <= moment && moment < $0.end }
    }

    private func nextCommitment(after moment: Date, context: NudgeContext) -> Commitment? {
        context.snapshot.commitments
            .filter { $0.start > moment }
            .min { lhs, rhs in lhs.start == rhs.start ? lhs.id < rhs.id : lhs.start < rhs.start }
    }
}

/// Deterministic nudge identifiers, scoped to the local day so a replan does not
/// duplicate a nudge and a scheduled local notification stays cancellable.
nonisolated enum NudgeIdentity {
    static func dayKey(_ day: Date, time: TimeContext) -> Int {
        Int(time.startOfDay(day).timeIntervalSince1970)
    }

    static func behindSchedule(day: Date, taskID: UUID, time: TimeContext) -> String {
        "\(dayKey(day, time: time))-behind-\(taskID.uuidString)"
    }

    static func eveningCheckIn(day: Date, time: TimeContext) -> String {
        "\(dayKey(day, time: time))-evening"
    }
}
