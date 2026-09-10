//
//  NudgeEngine.swift
//  Linea
//
//  Runs the nudge rules over an accepted plan and then applies the budget that
//  keeps Linea from becoming another notification machine: at most a few nudges
//  a day, a cooldown between interruptions, nothing during quiet hours (the
//  rules own that), and never a question the user has already answered.
//
//  Nudges are computed with their text ready so the moment a plan is accepted
//  they can be handed to the local-notification scheduler; `due(_:)` is what the
//  in-app check-in uses when the app is open.
//

import Foundation

nonisolated struct NudgeEngine: Sendable {
    let rules: [any NudgeRule]
    let renderer: any TextRenderer
    let config: EngineConfig

    init(rules: [any NudgeRule] = [BehindScheduleRule(), EveningCheckInRule()],
         renderer: any TextRenderer,
         config: EngineConfig = .default) {
        self.rules = rules
        self.renderer = renderer
        self.config = config
    }

    /// Every nudge planned for the rest of the day, in chronological order.
    func nudges(_ context: NudgeContext) -> [Nudge] {
        // The engine's config is the single configuration of a run, exactly as
        // in StateEngine: rules and budget must not disagree.
        let resolved = NudgeContext(
            plan: context.plan, snapshot: context.snapshot, state: context.state,
            feedback: context.feedback, existing: context.existing,
            calibration: context.calibration, config: config, time: context.time
        )

        let existingIDs = Set(resolved.existing.map(\.id))
        var seen = Set<String>()
        let candidates = rules.bound(to: renderer)
            .flatMap { $0.nudges(resolved) }
            .filter { !existingIDs.contains($0.id) && seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                if lhs.fireAt != rhs.fireAt { return lhs.fireAt < rhs.fireAt }
                if Self.rank(lhs.kind) != Self.rank(rhs.kind) { return Self.rank(lhs.kind) < Self.rank(rhs.kind) }
                return lhs.id < rhs.id
            }

        return capped(cooled(candidates, context: resolved), context: resolved)
    }

    /// Nudges whose moment has come and whose cancel condition has not fired.
    func due(_ context: NudgeContext) -> [Nudge] {
        let now = context.time.now
        let doneTaskIDs = Set(context.snapshot.tasks.filter(\.isDone).map(\.id))
        let rated = context.feedback.contains { $0.dayRating != nil }
        return nudges(context).filter { nudge in
            guard nudge.fireAt <= now else { return false }
            return !nudge.cancelWhen.contains { condition in
                switch condition {
                case .taskDone(let id): return doneTaskIDs.contains(id)
                case .dayRated: return rated
                case .planSuperseded: return context.plan.status == .superseded
                }
            }
        }
    }

    // MARK: - Budget

    /// The evening check-in is a ritual, not an interruption: it does not open a
    /// cooldown and is not silenced by one. Everything else has to wait its turn.
    private func cooled(_ candidates: [Nudge], context: NudgeContext) -> [Nudge] {
        let cooldown = TimeInterval(Double(config.nudgeCooldownMinutes) * max(1, context.calibration.nudgeCooldownMultiplier) * 60)
        var lastInterruption = context.existing
            .filter { $0.kind != .eveningCheckIn }
            .map(\.fireAt)
            .max()
        for feedback in context.feedback {
            guard case .nudgeResponse = feedback.kind else { continue }
            if lastInterruption == nil || feedback.at > lastInterruption! { lastInterruption = feedback.at }
        }

        var kept: [Nudge] = []
        for nudge in candidates {
            if nudge.kind == .eveningCheckIn {
                kept.append(nudge)
                continue
            }
            if let last = lastInterruption, nudge.fireAt.timeIntervalSince(last) < cooldown { continue }
            kept.append(nudge)
            lastInterruption = nudge.fireAt
        }
        return kept
    }

    private func capped(_ candidates: [Nudge], context: NudgeContext) -> [Nudge] {
        let room = max(0, config.maxNudgesPerDay - context.existing.count)
        guard candidates.count > room else { return candidates }
        return candidates
            .enumerated()
            .sorted { lhs, rhs in
                let l = Self.rank(lhs.element.kind), r = Self.rank(rhs.element.kind)
                if l != r { return l < r }
                return lhs.offset < rhs.offset
            }
            .prefix(room)
            .map(\.element)
            .sorted { $0.fireAt == $1.fireAt ? $0.id < $1.id : $0.fireAt < $1.fireAt }
    }

    /// Lower wins a contested slot: falling behind is more urgent than a rating.
    private static func rank(_ kind: NudgeKind) -> Int {
        switch kind {
        case .behindSchedule: return 0
        case .preCommitment: return 1
        case .morningBrief: return 2
        case .eveningCheckIn: return 3
        }
    }
}
