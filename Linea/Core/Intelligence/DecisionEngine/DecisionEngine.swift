//
//  DecisionEngine.swift
//  Linea
//
//  «Что делать сегодня»: a greedy, chronological, deterministic placement of
//  candidate tasks into the day's free windows (Docs/intelligence.md §7).
//
//  Two decisions shape everything here. First, the plan is a separate entity —
//  planning never touches a `LineaTask`, so «план vs факт» stays honest for the
//  Feedback Engine. Second, the engine writes no user-facing sentence itself:
//  every string comes from a `TextRenderer` fed with typed facts, so the LLM
//  (or the rule-based templates) can be swapped without touching the ordering.
//
//  The wow-scenario order (сложное утром, разработка после обеда) is NOT
//  hard-coded: it falls out of the circadian capacity curve plus the `.reduce`
//  constraints below.
//
//  What goes into a slot is decided by the priority engine (§16, ADR-025):
//  the task with the highest importance × action at that moment — important,
//  and reasonable to start there (fits the window, suits the energy of the
//  hour, not waiting for another task). «3 приоритетных действия» are ranked
//  by importance alone: what matters most today.
//

import Foundation

nonisolated struct DecisionEngine: Sendable {
    /// Stable machine reasons behind `Fact.taskDeferred` — codes, not sentences:
    /// the Russian wording belongs to the explainer, not to the planner.
    nonisolated enum DeferReason {
        /// The day's load cap was already reached.
        static let loadCap = "loadCap"
        /// No remaining window was long enough for the task.
        static let noWindow = "noWindow"
        /// The task waits for another one that does not finish today.
        static let blocked = "blocked"
    }

    /// Undated tasks are pulled in only when an active goal wants them or they
    /// are due this week, and only a few.
    static let maxUndatedGoalTasks = 3
    /// Cognitive demand from which a task counts as «deep» for the reduce rules.
    static let deepDemandThreshold = 0.7
    /// Non-deep minutes that must separate two deep blocks on a `.reduce` day.
    static let deepSeparationMinutes = 60
    /// End of the morning peak — the moment «самую сложную работу до …».
    static let peakWindowEnd = TimeOfDay(hour: 12)

    let rules: [any PlanRule]
    let renderer: any TextRenderer
    let config: EngineConfig
    private let priority: PriorityEngine

    init(rules: [any PlanRule] = [DayBriefRule()], renderer: any TextRenderer, config: EngineConfig = .default) {
        self.rules = rules
        self.renderer = renderer
        self.config = config
        self.priority = PriorityEngine(config: config)
    }

    // MARK: - Entry points

    func plan(
        snapshot: ContextSnapshot,
        state: UserState,
        calibration: Calibration = .default,
        time: TimeContext,
        planID: UUID
    ) -> DayPlan {
        build(
            snapshot: snapshot, state: state, calibration: calibration, time: time,
            planID: planID, from: time.now, preserved: [],
            version: 1, status: .proposed, createdAt: time.now, acceptedAt: nil
        )
    }

    /// Rebuilds the rest of the day from `time.now`. What already happened —
    /// finished blocks, anything the user marked done, anything pinned — is
    /// carried over untouched, because a plan the user already lived through
    /// is history, not a proposal.
    func replan(
        _ plan: DayPlan,
        snapshot: ContextSnapshot,
        state: UserState,
        calibration: Calibration = .default,
        time: TimeContext
    ) -> DayPlan {
        let now = time.now
        let doneTaskIDs = Set(snapshot.tasks.filter(\.isDone).map(\.id))
        let preserved = plan.blocks.filter { block in
            if block.end <= now { return true }
            if block.isPinned { return true }
            if let taskID = block.taskID, doneTaskIDs.contains(taskID) { return true }
            return false
        }
        return build(
            snapshot: snapshot, state: state, calibration: calibration, time: time,
            planID: plan.id, from: now, preserved: preserved,
            version: plan.version + 1, status: plan.status,
            createdAt: plan.createdAt, acceptedAt: plan.acceptedAt
        )
    }

    // MARK: - Build

    private func build(
        snapshot: ContextSnapshot,
        state: UserState,
        calibration: Calibration,
        time: TimeContext,
        planID: UUID,
        from: Date,
        preserved: [PlanBlock],
        version: Int,
        status: PlanStatus,
        createdAt: Date,
        acceptedAt: Date?
    ) -> DayPlan {
        let day = time.startOfDay(snapshot.day)
        let profile = snapshot.profile
        let taskByID = Dictionary(snapshot.tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let preservedIDs = Set(preserved.map(\.id))
        let preservedTaskIDs = Set(preserved.compactMap(\.taskID))

        let priorityContext = PriorityContext(snapshot: snapshot, state: state, calibration: calibration, config: config, time: time)
        let candidates = priority.candidates(context: priorityContext)
        let commitments = allCommitments(snapshot: snapshot, candidates: candidates, calibration: calibration, time: time)

        // Time the planner may not touch: commitments plus preserved blocks
        // that reach into the future (a pinned block, a finished-late block).
        let preservedBusy = preserved.filter { $0.end > from }.map { block in
            Commitment(id: "preserved-\(block.id)", title: block.title, start: block.start, end: block.end,
                       kind: .other, source: .tasks, taskID: block.taskID)
        }
        let windows = FreeWindows.compute(
            day: day, now: from, profile: profile,
            commitments: commitments + preservedBusy, config: config, time: time
        )

        let placement = place(
            candidates: candidates,
            excluding: preservedTaskIDs.union(Set(commitments.compactMap(\.taskID))),
            windows: windows, preserved: preserved, commitments: commitments,
            from: from, context: priorityContext, planID: planID
        )

        // «Без даты» (§18): все задачи дня встали, а время осталось — Linea сама
        // ставит туда пару задач из входящих, в пределах той же нагрузки. Если
        // задачи дня переносятся из-за нагрузки или окон, входящие ждут. Не
        // поместились — не перенос: дня у них не было.
        let dayIsFull = placement.deferred.contains { $0.reason != DeferReason.blocked }
        let picks = dayIsFull ? [] : priority.inboxPicks(context: priorityContext).filter { !preservedTaskIDs.contains($0.id) }
        let inboxBlocks = picks.isEmpty ? [] : place(
            candidates: picks, excluding: Set(commitments.compactMap(\.taskID)),
            windows: Self.gaps(in: windows, around: placement.blocks, bufferMinutes: config.blockBufferMinutes),
            preserved: preserved + placement.blocks, commitments: commitments,
            from: from, context: priorityContext, planID: planID,
            budget: (used: placement.usedMinutes, cap: placement.capMinutes)
        ).blocks

        var blocks = preserved
        blocks += commitmentBlocks(commitments, context: priorityContext, planID: planID, from: from,
                                   taskByID: taskByID, skipping: preservedIDs)
        blocks += placement.blocks
        blocks += inboxBlocks
        blocks.sort(by: Self.chronological)

        // Top actions: the most important tasks that actually made it into the
        // day, fixed ones included — «3 приоритетных действия» is a ranking of
        // what will happen, not of what was requested. Tasks from «Без даты»
        // only fill leftover time, so they are never the day's priorities.
        let activeGoalIDs = Set(snapshot.goals.filter { $0.isActive && !$0.isCompleted }.map(\.id))
        let rankable = blocks.filter { block in
            guard let task = block.taskID.flatMap({ taskByID[$0] }) else { return true }
            return !Self.isInboxFiller(task, activeGoalIDs: activeGoalIDs)
        }
        let ranking = rank(blocks: rankable, taskByID: taskByID, context: priorityContext)
        let topTaskIDs = Array(ranking.prefix(config.maxTopTasks).map(\.taskID))
        let topSet = Set(topTaskIDs)
        let scoreByTask = Dictionary(ranking.map { ($0.taskID, $0.score) }, uniquingKeysWith: { a, _ in a })
        for index in blocks.indices {
            guard let taskID = blocks[index].taskID else { continue }
            blocks[index].isTop = topSet.contains(taskID)
            if blocks[index].score == nil { blocks[index].score = scoreByTask[taskID] }
        }

        var facts: [Fact] = [.topTaskCount(topTaskIDs.count)]
        if let deadline = hardWorkDeadline(in: blocks, taskByID: taskByID, day: day, time: time) {
            facts.append(.hardWorkDeadline(deadline))
        }
        facts += blocks.flatMap(\.facts)
        facts += placement.deferred.map {
            .taskDeferred(taskID: $0.task.id, title: $0.task.title, reason: $0.reason)
        }

        var plan = DayPlan(
            id: planID, day: day, version: version, status: status, createdAt: createdAt,
            acceptedAt: acceptedAt, snapshotID: snapshot.id, blocks: blocks,
            topTaskIDs: topTaskIDs, deferredTaskIDs: placement.deferred.map(\.task.id),
            recommendations: [], facts: facts
        )

        let context = PlanningContext(snapshot: snapshot, state: state, calibration: calibration,
                                      config: config, time: time, freeWindows: windows)
        var produced: [Recommendation] = []
        for rule in rules.bound(to: renderer) {
            produced += rule.apply(to: &plan, context: context)
        }
        plan.recommendations = Self.byPriority(produced)
        plan.blocks.sort(by: Self.chronological)
        return plan
    }

    // MARK: - Candidates

    /// Open tasks for today, overdue tasks, tasks whose deadline is within two
    /// days, plus a few undated tasks that serve an active goal or are due this
    /// week — chosen by the priority engine (`PriorityEngine.candidates`).
    func candidateTasks(snapshot: ContextSnapshot, state: UserState, calibration: Calibration, time: TimeContext) -> [LineaTask] {
        priority.candidates(context: PriorityContext(snapshot: snapshot, state: state, calibration: calibration, config: config, time: time))
    }

    /// Snapshot commitments plus a synthesized one for every candidate task the
    /// user pinned to a clock time that no connector reported yet.
    private func allCommitments(snapshot: ContextSnapshot, candidates: [LineaTask], calibration: Calibration, time: TimeContext) -> [Commitment] {
        var result = snapshot.commitments
        let covered = Set(snapshot.commitments.compactMap(\.taskID))
        for task in candidates where task.isFixed && !covered.contains(task.id) {
            guard let start = task.scheduledStart else { continue }
            let minutes = PlanDuration.minutes(for: task, calibration: calibration)
            result.append(Commitment(
                id: "task-\(task.id.uuidString)", title: task.title, start: start,
                end: start.addingTimeInterval(TimeInterval(minutes * 60)),
                kind: .task, source: .tasks, taskID: task.id
            ))
        }
        return result.sorted { lhs, rhs in
            lhs.start == rhs.start ? lhs.id < rhs.id : lhs.start < rhs.start
        }
    }

    // MARK: - Greedy placement

    private struct Deferred {
        let task: LineaTask
        let reason: String
    }

    private struct Placement {
        let blocks: [PlanBlock]
        let deferred: [Deferred]
        /// Сколько минут дня заняли задачи и сколько разрешала нагрузка.
        let usedMinutes: Int
        let capMinutes: Int
    }

    /// `budget` — нагрузка, уже набранная прошлым проходом: второй проход
    /// (задачи «Без даты») досыпает в тот же предел, а не в новый.
    private func place(
        candidates: [LineaTask],
        excluding excluded: Set<UUID>,
        windows: [DateInterval],
        preserved: [PlanBlock],
        commitments: [Commitment],
        from: Date,
        context: PriorityContext,
        planID: UUID,
        budget: (used: Int, cap: Int)? = nil
    ) -> Placement {
        let snapshot = context.snapshot
        let state = context.state
        let calibration = context.calibration
        let time = context.time
        var remaining = candidates.filter { !$0.isFixed && !excluded.contains($0.id) }
        let availableMinutes = windows.reduce(0.0) { $0 + $1.duration / 60 }
        let capMinutes = budget?.cap
            ?? Int((availableMinutes * capacityFactorDay(state: state, calibration: calibration)).rounded(.down))

        var blocks: [PlanBlock] = []
        var usedMinutes = budget?.used ?? 0
        var capBlocked = Set<UUID>()
        var lastDeepEnd = preserved
            .filter { $0.kind == .focus && isDeep($0.taskID, in: snapshot) }
            .map(\.end).max()
        // When each task is over by the plan: a task that waits for another
        // («Сначала нужно») may only start after it. Fixed tasks end with their
        // commitment; blocks kept from the plan already lived through only count
        // if they are still ahead.
        var finishes: [UUID: Date] = [:]
        for block in preserved where block.end > from {
            if let taskID = block.taskID { finishes[taskID] = block.end }
        }
        for commitment in commitments {
            if let taskID = commitment.taskID { finishes[taskID] = commitment.end }
        }

        for window in windows {
            var cursor = window.start
            while true {
                let windowMinutes = Int(window.end.timeIntervalSince(cursor) / 60)
                guard windowMinutes >= config.minimumBlockMinutes else { break }
                let finished = Set(finishes.filter { $0.value <= cursor }.keys)

                var best: (task: LineaTask, minutes: Int, assessment: PriorityAssessment)?
                for task in remaining {
                    let planned = PlanDuration.minutes(for: task, calibration: calibration)
                    // Half a task in a leftover window is worse than moving it to
                    // the next one — unless most of it still fits.
                    if planned > windowMinutes, Double(windowMinutes) < 0.8 * Double(planned) { continue }
                    let minutes = min(planned, windowMinutes)
                    guard minutes >= config.minimumBlockMinutes else { continue }
                    if usedMinutes + minutes > capMinutes {
                        capBlocked.insert(task.id)
                        continue
                    }
                    guard deepRulesAllow(task: task, start: cursor, lastDeepEnd: lastDeepEnd, state: state, time: time) else { continue }
                    let assessment = priority.assess(task, at: cursor, windowMinutes: windowMinutes,
                                                     context: context, assumingDone: finished)
                    // Waiting for a task that is not over yet at this moment.
                    guard assessment.actionFactors.gate > 0 else { continue }
                    if best == nil || assessment.focus > best!.assessment.focus {
                        best = (task, minutes, assessment)
                    }
                }
                guard let choice = best else { break }

                let end = cursor.addingTimeInterval(TimeInterval(choice.minutes * 60))
                blocks.append(PlanBlock(
                    id: "\(planID.uuidString)-\(choice.task.id.uuidString)",
                    kind: .focus, taskID: choice.task.id, title: choice.task.title,
                    start: cursor, end: end, score: choice.assessment.breakdown,
                    facts: [.taskPlanned(taskID: choice.task.id, title: choice.task.title, start: cursor, end: end)]
                ))
                usedMinutes += choice.minutes
                finishes[choice.task.id] = end
                if choice.task.cognitiveDemand.score >= Self.deepDemandThreshold { lastDeepEnd = end }
                remaining.removeAll { $0.id == choice.task.id }
                cursor = end.addingTimeInterval(TimeInterval(config.blockBufferMinutes * 60))
            }
        }

        let planned = Set(finishes.keys)
        let deferred = remaining.map { task -> Deferred in
            let reason: String
            if !context.dependencies.openBlockers(of: task.id, assumingDone: planned).isEmpty {
                reason = DeferReason.blocked
            } else if capBlocked.contains(task.id) {
                reason = DeferReason.loadCap
            } else {
                reason = DeferReason.noWindow
            }
            return Deferred(task: task, reason: reason)
        }
        return Placement(blocks: blocks, deferred: deferred, usedMinutes: usedMinutes, capMinutes: capMinutes)
    }

    /// A task the plan only takes into leftover time: no day, no deadline, no
    /// time of its own and no active goal — it is never a day candidate.
    static func isInboxFiller(_ task: LineaTask, activeGoalIDs: Set<UUID>) -> Bool {
        task.date == nil && task.deadline == nil && task.scheduledStart == nil
            && !(task.goalID.map(activeGoalIDs.contains) ?? false)
    }

    /// Свободное время окон вокруг уже поставленных блоков — с буфером до и
    /// после каждого, как между блоками одного прохода.
    static func gaps(in windows: [DateInterval], around blocks: [PlanBlock], bufferMinutes: Int) -> [DateInterval] {
        let buffer = TimeInterval(bufferMinutes * 60)
        let busy = blocks
            .map { DateInterval(start: $0.start.addingTimeInterval(-buffer), end: $0.end.addingTimeInterval(buffer)) }
            .sorted { $0.start < $1.start }
        var result: [DateInterval] = []
        for window in windows {
            var cursor = window.start
            for interval in busy where interval.end > cursor && interval.start < window.end {
                if interval.start > cursor { result.append(DateInterval(start: cursor, end: interval.start)) }
                cursor = max(cursor, interval.end)
            }
            if cursor < window.end { result.append(DateInterval(start: cursor, end: window.end)) }
        }
        return result
    }

    /// How much of the free time the day may actually be filled with.
    private func capacityFactorDay(state: UserState, calibration: Calibration) -> Double {
        let byAdvice: Double
        switch state.loadAdvice {
        case .reduce: byAdvice = config.loadCapReduced
        case .normal: byAdvice = config.loadCapNormal
        case .push: byAdvice = 1.1
        case .unknown: byAdvice = 0.9
        }
        return max(0, calibration.capacityFactor * byAdvice)
    }

    /// On a `.reduce` day deep work is rationed: never late in the day, and
    /// never twice in a row without a real break in between.
    private func deepRulesAllow(task: LineaTask, start: Date, lastDeepEnd: Date?, state: UserState, time: TimeContext) -> Bool {
        guard state.loadAdvice == .reduce else { return true }
        guard task.cognitiveDemand.score >= Self.deepDemandThreshold else { return true }
        if time.hourFraction(of: start) >= Double(config.deepWorkLatestHourWhenReduced) { return false }
        if let lastDeepEnd, start.timeIntervalSince(lastDeepEnd) < TimeInterval(Self.deepSeparationMinutes * 60) { return false }
        return true
    }

    private func isDeep(_ taskID: UUID?, in snapshot: ContextSnapshot) -> Bool {
        guard let taskID, let task = snapshot.tasks.first(where: { $0.id == taskID }) else { return false }
        return task.cognitiveDemand.score >= Self.deepDemandThreshold
    }

    // MARK: - Commitment blocks

    private func commitmentBlocks(
        _ commitments: [Commitment],
        context: PriorityContext,
        planID: UUID,
        from: Date,
        taskByID: [UUID: LineaTask],
        skipping preservedIDs: Set<String>
    ) -> [PlanBlock] {
        let snapshot = context.snapshot
        let time = context.time
        return commitments.compactMap { commitment -> PlanBlock? in
            guard commitment.end > from else { return nil }
            let id = commitment.taskID.map { "\(planID.uuidString)-\($0.uuidString)" }
                ?? "\(planID.uuidString)-c-\(commitment.id)"
            guard !preservedIDs.contains(id) else { return nil }

            var facts: [Fact] = []
            switch commitment.kind {
            case .workout: facts.append(.workoutPlanned(at: commitment.start))
            case .meal:
                facts.append(.mealWindow(kind: mealKind(for: commitment, snapshot: snapshot, time: time),
                                         start: commitment.start, end: commitment.end))
            default: break
            }

            var score: ScoreBreakdown?
            if let taskID = commitment.taskID, let task = taskByID[taskID] {
                score = priority.assess(task, at: commitment.start, windowMinutes: max(commitment.durationMinutes, 1),
                                        context: context).breakdown
            }

            return PlanBlock(
                id: id, kind: commitment.kind == .meal ? .meal : .commitment,
                taskID: commitment.taskID, title: commitment.title,
                start: commitment.start, end: commitment.end, score: score, facts: facts
            )
        }
    }

    private func mealKind(for commitment: Commitment, snapshot: ContextSnapshot, time: TimeContext) -> MealKind {
        let start = time.timeOfDay(of: commitment.start)
        if let window = snapshot.nutrition?.mealWindows.first(where: { $0.start == start }) {
            return window.kind
        }
        switch start.hour {
        case ..<11: return .breakfast
        case ..<16: return .lunch
        case ..<21: return .dinner
        default: return .snack
        }
    }

    // MARK: - Ranking & facts

    private struct Ranked {
        let taskID: UUID
        let task: LineaTask
        let score: ScoreBreakdown
    }

    private func rank(blocks: [PlanBlock], taskByID: [UUID: LineaTask], context: PriorityContext) -> [Ranked] {
        var seen = Set<UUID>()
        var ranked: [Ranked] = []
        for block in blocks {
            guard block.kind != .rest, let taskID = block.taskID, let task = taskByID[taskID] else { continue }
            guard seen.insert(taskID).inserted else { continue }
            // Blocks kept from a plan made before the priority engine have no
            // importance yet — it is computed for their start.
            let score: ScoreBreakdown
            if let stored = block.score, stored.importanceScore != nil {
                score = stored
            } else {
                score = priority.assess(task, at: block.start, windowMinutes: max(block.durationMinutes, 1),
                                        context: context).breakdown
            }
            ranked.append(Ranked(taskID: taskID, task: task, score: score))
        }
        return ranked.sorted { lhs, rhs in
            let left = lhs.score.importanceScore ?? 0
            let right = rhs.score.importanceScore ?? 0
            if left != right { return left > right }
            if lhs.score.total != rhs.score.total { return lhs.score.total > rhs.score.total }
            return Self.chronological(lhs.task, rhs.task)
        }
    }

    /// «Самую сложную работу предлагаю сделать до 12:00» — stated only when the
    /// hardest task of the day really does fit inside the morning peak.
    private func hardWorkDeadline(in blocks: [PlanBlock], taskByID: [UUID: LineaTask], day: Date, time: TimeContext) -> Date? {
        let focus = blocks.compactMap { block -> (block: PlanBlock, task: LineaTask)? in
            guard block.kind == .focus, let taskID = block.taskID, let task = taskByID[taskID] else { return nil }
            return (block, task)
        }
        let hardest = focus.max { lhs, rhs in
            let l = lhs.task.cognitiveDemand.score, r = rhs.task.cognitiveDemand.score
            if l != r { return l < r }
            let ls = lhs.block.score?.total ?? 0, rs = rhs.block.score?.total ?? 0
            if ls != rs { return ls < rs }
            return !Self.chronological(lhs.task, rhs.task)
        }
        guard let hardest else { return nil }
        let peakEnd = time.date(on: day, at: Self.peakWindowEnd)
        return hardest.block.end <= peakEnd ? peakEnd : nil
    }

    // MARK: - Deterministic ordering

    static func chronological(_ lhs: LineaTask, _ rhs: LineaTask) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    static func chronological(_ lhs: PlanBlock, _ rhs: PlanBlock) -> Bool {
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        if lhs.end != rhs.end { return lhs.end < rhs.end }
        return lhs.id < rhs.id
    }

    /// Highest priority first, insertion order preserved inside a priority.
    static func byPriority(_ recommendations: [Recommendation]) -> [Recommendation] {
        recommendations.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.priority != rhs.element.priority { return lhs.element.priority > rhs.element.priority }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
