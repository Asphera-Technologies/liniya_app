//
//  PriorityEngine.swift
//  Linea
//
//  Движок приоритизации v1 (Docs/intelligence.md §16, ADR-025). Одного общего
//  балла нет — у задачи две оценки:
//
//    importance = Σ w·f / Σ w — приоритет человека, важность и срок цели,
//                           срок и просрочка задачи, тип, сколько задач её
//                           ждут, сколько раз переносили. Без цели задача
//                           оценивается по своим признакам, а связь с целью
//                           может её только поднять: goal_id = null
//                           ценности не снижает;
//    action = gate × fit × (0.5 + 0.5·pull)
//      gate — 0, если сейчас нельзя: ждёт другую задачу, у неё своё время,
//             сейчас занято;
//      fit  — хватит ли окна до следующего дела и сил на такую сложность;
//      pull — поджимает ли срок, на сегодня ли задача, ритм и баланс дня.
//
//  Планировщик ставит в каждое окно задачу с наибольшим importance × action,
//  «главное сегодня» — по importance, «сейчас» — по importance × action в эту
//  минуту. Пять факторов брифа (`TaskScorer`) остались — это кирпичи обеих
//  оценок и объяснение в каждом блоке плана.
//
//  Как и остальное ядро — чистая функция от данных: тот же вход в тот же
//  момент даёт тот же ответ, поэтому всё закреплено тестами.
//

import Foundation

nonisolated struct PriorityEngine: Sendable {
    /// Задачи без дня, которые попадают в план, если у них срок на этой неделе.
    static let undatedDeadlineDays = 7
    /// За сколько минут до назначенного времени задача уже «сейчас».
    static let fixedLeadMinutes = 10
    /// Сколько стоит в `day` задача без дня и задача на другой день.
    static let undatedDay = 0.6
    static let laterDay = 0.2
    /// Ритм по умолчанию и окно «продолжаю ту же цель».
    static let baseRhythm = 0.9
    static let momentumMinutes = 90
    /// Баланс: сколько тянет задача, когда задач этого типа сегодня закрыто 0, 1, 2, 3+.
    static let balance = [1.0, 0.95, 0.85, 0.7]
    /// Ниже этого `energyFit` у задачи появляется ограничение «мало сил».
    static let lowEnergyFit = 0.5
    /// С какого числа переносов вес переносов полный.
    static let deferralsForFullWeight = 3
    /// Сколько задач из «Без даты» Linea сама ставит в свободное время дня.
    static let maxInboxPicks = 2

    let config: EngineConfig
    private let scorer = TaskScorer()
    private let classifier = TaskClassifier()

    init(config: EngineConfig = .default) {
        self.config = config
    }

    // MARK: - importance_score

    /// «Насколько задача важна вообще». От момента зависит только через сроки.
    ///
    /// Задача без цели — полноценная задача (goal_id = null ценности не
    /// снижает): её важность — по её собственным признакам, а вес цели
    /// делится между ними. Связь с целью может задачу только поднять: важна
    /// большая из двух оценок — сама по себе и как шаг к цели.
    func importance(of task: LineaTask, at moment: Date, context: PriorityContext) -> (score: Double, factors: ImportanceFactors) {
        let planned = PlanDuration.minutes(for: task, calibration: context.calibration)
        let goal = context.snapshot.goals.contains { $0.id == task.goalID } ? goalFactor(of: task, at: moment, context: context) : nil
        let factors = ImportanceFactors(
            priority: task.priority.score,
            goal: goal ?? 0,
            deadline: scorer.urgency(task: task, plannedMinutes: planned, at: moment, profile: context.profile, time: context.time),
            kind: Self.kindWeight(classifier.kind(of: task)),
            dependents: Self.dependentsWeight(context.dependencies.dependents(of: task.id)),
            deferrals: min(1, Double(task.deferralCount) / Double(Self.deferralsForFullWeight))
        )
        let c = config
        // Сама по себе: тип — по словам названия, как если бы цели не было.
        var own = factors
        own.kind = Self.kindWeight(classifier.classify(
            title: task.title, goalID: nil, isFixed: task.isFixed, demand: task.cognitiveDemand, override: task.kindOverride
        ).kind)
        let alone = weighted(own, goalWeight: 0)
        guard let goal else { return (alone, factors) }
        var linked = factors
        linked.goal = goal
        return (max(alone, weighted(linked, goalWeight: c.importanceWeightGoal)), factors)
    }

    /// Σ w·f / Σ w; цель — со своим весом или без него.
    private func weighted(_ factors: ImportanceFactors, goalWeight: Double) -> Double {
        let c = config
        let weights = c.importanceWeightPriority + goalWeight + c.importanceWeightDeadline
            + c.importanceWeightKind + c.importanceWeightDependents + c.importanceWeightDeferrals
        var sum = c.importanceWeightPriority * factors.priority
        sum += goalWeight * factors.goal
        sum += c.importanceWeightDeadline * factors.deadline
        sum += c.importanceWeightKind * factors.kind
        sum += c.importanceWeightDependents * factors.dependents
        sum += c.importanceWeightDeferrals * factors.deferrals
        return weights > 0 ? StateMath.clamp(sum / weights) : 0
    }

    /// Цель задачи: насколько близок её срок (`TaskScorer.goalAlignment`) и
    /// насколько она важна сама по себе.
    func goalFactor(of task: LineaTask, at moment: Date, context: PriorityContext) -> Double {
        guard let goalID = task.goalID,
              let goal = context.snapshot.goals.first(where: { $0.id == goalID }) else { return 0 }
        let alignment = scorer.goalAlignment(task: task, snapshot: context.snapshot, at: moment, time: context.time)
        return StateMath.clamp(alignment * Self.goalWeight(goal.priority))
    }

    /// Важность цели: средняя ничего не меняет, высокая поднимает, низкая опускает.
    static func goalWeight(_ priority: TaskPriority) -> Double {
        switch priority {
        case .low: return 0.7
        case .normal: return 1.0
        case .important: return 1.2
        }
    }

    /// Тип: шаг к цели и обещанное другим важнее быта и рутины.
    static func kindWeight(_ kind: TaskKind) -> Double {
        switch kind {
        case .goal: return 1.0
        case .obligation: return 0.9
        case .incoming: return 0.6
        case .maintenance: return 0.5
        case .standalone: return 0.5
        case .routine: return 0.4
        }
    }

    /// Задача, которую ждут другие, важнее: она их разблокирует.
    static func dependentsWeight(_ count: Int) -> Double {
        switch count {
        case 0: return 0
        case 1: return 0.6
        default: return 1
        }
    }

    // MARK: - action_score и оценка целиком

    /// Обе оценки задачи в момент `moment` (по умолчанию — сейчас). Окно —
    /// `windowMinutes`, если его знает планировщик, иначе — до ближайшего
    /// обязательства. `done` — задачи, которые к этому моменту будут сделаны
    /// по плану: они уже не держат зависящие от них.
    func assess(
        _ task: LineaTask,
        at moment: Date? = nil,
        windowMinutes: Int? = nil,
        context: PriorityContext,
        assumingDone done: Set<UUID> = []
    ) -> PriorityAssessment {
        let time = context.time
        let moment = moment ?? time.now
        let (importance, importanceFactors) = self.importance(of: task, at: moment, context: context)
        let needed = PlanDuration.minutes(for: task, calibration: context.calibration)
        var limits: [ActionLimit] = []
        var gate = task.isDone ? 0.0 : 1.0

        if let blocker = context.dependencies.openBlockers(of: task.id, assumingDone: done).first {
            gate = 0
            limits.append(.blocked(by: blocker))
        }
        if let start = task.scheduledStart {
            let opens = start.addingTimeInterval(-TimeInterval(Self.fixedLeadMinutes * 60))
            let closes = start.addingTimeInterval(TimeInterval(needed * 60))
            if moment < opens || moment >= closes {
                gate = 0
                limits.append(.fixedTime(start))
            }
        }

        let available: Int
        if let windowMinutes {
            available = max(0, windowMinutes)
        } else {
            let window = context.window(at: moment, excluding: task.id)
            available = window.minutes
            if window.isBusy {
                gate = 0
                limits.append(.busy)
            }
        }
        let windowFit: Double
        if available >= needed {
            windowFit = 1
        } else if Double(available) >= 0.8 * Double(needed) {
            // Планировщик ставит задачу, если влезает 80 %: остальное — после.
            windowFit = 0.8
        } else {
            windowFit = scorer.durationFit(plannedMinutes: needed, windowMinutes: available, config: config)
        }
        if available < needed, !limits.contains(.busy) {
            limits.append(.shortWindow(minutesLeft: available, minutesNeeded: needed))
        }

        let energy = scorer.energyFit(task: task, at: moment, state: context.state, config: config, time: time)
        if let energy, energy < Self.lowEnergyFit { limits.append(.lowEnergy) }

        let deadline = scorer.urgency(task: task, plannedMinutes: needed, at: moment, profile: context.profile, time: time)

        let day: Double
        if let date = task.date {
            let taskDay = time.startOfDay(date)
            if taskDay <= time.startOfDay(moment) {
                day = 1
            } else {
                day = Self.laterDay
                limits.append(.plannedLater(taskDay))
            }
        } else {
            day = Self.undatedDay
        }

        let kind = classifier.kind(of: task)
        var rhythm = Self.baseRhythm
        if let goalID = task.goalID, context.recent.last(before: moment, within: Self.momentumMinutes)?.goalID == goalID {
            rhythm = 1
        }
        if task.cognitiveDemand.score >= DecisionEngine.deepDemandThreshold {
            let deepMinutes = context.recent.deepMinutes(before: moment)
            if deepMinutes >= 150 {
                rhythm = min(rhythm, 0.6)
            } else if deepMinutes >= 90 {
                rhythm = min(rhythm, 0.8)
            }
        }
        let sameKind = context.recent.count(of: kind, before: moment)
        let balance = Self.balance[min(sameKind, Self.balance.count - 1)]

        let factors = ActionFactors(
            window: windowFit, energy: energy, deadline: deadline, day: day,
            rhythm: rhythm, balance: balance, gate: gate
        )
        let c = config
        let pullWeights = c.actionWeightDeadline + c.actionWeightDay + c.actionWeightRhythm + c.actionWeightBalance
        var pull = c.actionWeightDeadline * deadline + c.actionWeightDay * day
        pull += c.actionWeightRhythm * rhythm + c.actionWeightBalance * balance
        pull = pullWeights > 0 ? pull / pullWeights : 1
        // Мало сил режет уместность, но не обнуляет: бывает, что сложное
        // всё равно нужно сейчас.
        let fit = windowFit * (energy.map { 0.4 + 0.6 * $0 } ?? 1)
        let action = StateMath.clamp(gate * fit * (0.5 + 0.5 * pull))

        let breakdown = ScoreBreakdown(
            urgency: deadline,
            importance: scorer.importance(task: task, snapshot: context.snapshot, at: moment, time: time),
            goalAlignment: scorer.goalAlignment(task: task, snapshot: context.snapshot, at: moment, time: time),
            energyFit: energy,
            durationFit: scorer.durationFit(plannedMinutes: needed, windowMinutes: available, config: config),
            total: importance * action,
            importanceScore: importance,
            actionScore: action
        )
        return PriorityAssessment(
            taskID: task.id, kind: kind, importance: importance, action: action,
            importanceFactors: importanceFactors, actionFactors: factors, limits: limits,
            minutesNeeded: needed, minutesAvailable: available, breakdown: breakdown
        )
    }

    // MARK: - Кандидаты и «сейчас»

    /// Кандидаты дня (§7): открытые задачи на сегодня и просроченные, со
    /// сроком в ближайшие два дня, плюс до трёх задач без дня — к активной
    /// цели или со сроком на этой неделе («на неделе») — самые важные.
    func candidates(context: PriorityContext) -> [LineaTask] {
        let time = context.time
        let snapshot = context.snapshot
        let today = time.startOfDay(snapshot.day)
        let deadlineHorizon = time.adding(days: 3, to: today)   // «≤ today + 2» = strictly before today + 3
        let weekHorizon = time.adding(days: Self.undatedDeadlineDays + 1, to: today)
        var picked: [LineaTask] = []
        var undated: [LineaTask] = []

        for task in snapshot.tasks where !task.isDone {
            if let date = task.date, time.startOfDay(date) <= today {
                picked.append(task)
                continue
            }
            if let deadline = task.deadline, deadline < deadlineHorizon {
                picked.append(task)
                continue
            }
            guard task.date == nil else { continue }
            let servesGoal = task.goalID
                .flatMap { goalID in snapshot.goals.first { $0.id == goalID } }
                .map { $0.isActive && !$0.isCompleted } ?? false
            let dueThisWeek = task.deadline.map { $0 < weekHorizon } ?? false
            if servesGoal || dueThisWeek { undated.append(task) }
        }

        let extras = undated
            .map { task in (task: task, importance: importance(of: task, at: time.now, context: context).score) }
            .sorted { lhs, rhs in
                if lhs.importance != rhs.importance { return lhs.importance > rhs.importance }
                return DecisionEngine.chronological(lhs.task, rhs.task)
            }
            .prefix(DecisionEngine.maxUndatedGoalTasks)
            .map { $0.task }

        return (picked + extras).sorted(by: DecisionEngine.chronological)
    }

    /// «Без даты» (§18): Linea сама подбирает место паре задач из входящих —
    /// самым важным, кроме «не срочных» (низкий приоритет). В план они встают
    /// только в то время, что осталось после задач дня (`DecisionEngine`), и
    /// не поместились — не перенос: дня у них не было.
    func inboxPicks(context: PriorityContext) -> [LineaTask] {
        let time = context.time
        let activeGoals = Set(context.snapshot.goals.filter { $0.isActive && !$0.isCompleted }.map(\.id))
        return context.snapshot.tasks
            .filter { task in
                // Задачи к активной цели и так среди кандидатов дня.
                InboxReview.isInInbox(task) && task.priority != .low
                    && !(task.goalID.map(activeGoals.contains) ?? false)
            }
            .map { task in (task: task, importance: importance(of: task, at: time.now, context: context).score) }
            .sorted { lhs, rhs in
                if lhs.importance != rhs.importance { return lhs.importance > rhs.importance }
                return DecisionEngine.chronological(lhs.task, rhs.task)
            }
            .prefix(Self.maxInboxPicks)
            .map(\.task)
    }

    /// «Что делать сейчас»: кандидаты дня и задачи «Без даты», которым Linea
    /// подобрала место, в момент `context.time.now`. Впереди — важные и
    /// уместные сейчас (`focus`); при равенстве — важнее, потом раньше созданные.
    /// Задача без дня тянет слабее задачи на сегодня (`undatedDay`), поэтому
    /// встаёт впереди, только когда важнее.
    func rankNow(context: PriorityContext) -> [PriorityAssessment] {
        let candidates = candidates(context: context)
        let known = Set(candidates.map(\.id))
        let picks = inboxPicks(context: context).filter { !known.contains($0.id) }
        return (candidates + picks)
            .map { assess($0, context: context) }
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.focus != rhs.element.focus { return lhs.element.focus > rhs.element.focus }
                if lhs.element.importance != rhs.element.importance { return lhs.element.importance > rhs.element.importance }
                return lhs.offset < rhs.offset
            }
            .map { $0.element }
    }
}
