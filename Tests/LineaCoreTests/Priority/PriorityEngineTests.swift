import Testing
import Foundation
@testable import LineaCore

/// Пример из постановки: «Подготовить стратегию» — высокий приоритет, 90 минут.
/// В 15:30 до встречи 20 минут, встреча 15:50–16:20. Среда 9 сентября 2026.
nonisolated private enum Strategy {
    static let strategy = UUID(uuidString: "51000000-0000-0000-0000-000000000001")!
    static let mail = UUID(uuidString: "51000000-0000-0000-0000-000000000002")!

    static var meeting: Commitment {
        Commitment(id: "meeting", title: "Встреча с клиентом", start: WowFixture.moment(15, 50),
                   end: WowFixture.moment(16, 20), kind: .meeting, source: .calendar)
    }

    static var tasks: [LineaTask] {
        [
            LineaTask(id: strategy, title: "Подготовить стратегию", date: WowFixture.today, priority: .important,
                      createdAt: WowFixture.created, estimatedMinutes: 90, cognitiveDemand: .deep),
            LineaTask(id: mail, title: "Ответить на письма", date: WowFixture.today, priority: .normal,
                      createdAt: WowFixture.created.addingTimeInterval(60), estimatedMinutes: 15, cognitiveDemand: .light),
        ]
    }

    static func state(at time: TimeContext) -> UserState {
        PlanFixture.state(energy: 0.6, confidence: 0.8, advice: .normal, at: time)
    }

    static func context(at time: TimeContext, tasks: [LineaTask] = tasks, commitments: [Commitment] = [meeting]) -> PriorityContext {
        PriorityContext(snapshot: PlanFixture.snapshot(tasks: tasks, commitments: commitments, at: time),
                        state: state(at: time), time: time)
    }

    static func record(at time: TimeContext, tasks: [LineaTask] = tasks, plan: DayPlan? = nil) -> DayRecord {
        DayRecord(day: WowFixture.today, snapshot: PlanFixture.snapshot(tasks: tasks, commitments: [meeting], at: time),
                  state: state(at: time), plan: plan, updatedAt: time.now)
    }
}

@Suite("Движок приоритизации")
struct PriorityEngineTests {
    private let engine = PriorityEngine()

    private func task(_ id: UUID, in tasks: [LineaTask]) -> LineaTask {
        tasks.first { $0.id == id }!
    }

    // MARK: Две оценки

    @Test("Стратегия за 20 минут до встречи: важность высокая, уместность низкая; после встречи — высокая")
    func strategyBeforeAndAfterMeeting() {
        let before = WowFixture.time(15, 30)
        let strategy = task(Strategy.strategy, in: Strategy.tasks)
        let early = engine.assess(strategy, context: Strategy.context(at: before))
        #expect(early.importance > 0.6)
        #expect(early.action < 0.25)
        #expect(early.minutesAvailable == 20)
        #expect(early.limits.contains(.shortWindow(minutesLeft: 20, minutesNeeded: 90)))

        let after = WowFixture.time(16, 20)
        let late = engine.assess(strategy, context: Strategy.context(at: after))
        #expect(late.importance > 0.6)
        #expect(late.action > 0.6)
        #expect(late.limits.isEmpty)
        // Важность от встречи не зависит — меняется только уместность.
        #expect(abs(late.importance - early.importance) < 0.05)
    }

    @Test("Во время встречи браться нельзя ни за что")
    func busyDuringMeeting() {
        let during = WowFixture.time(16, 0)
        let mail = engine.assess(task(Strategy.mail, in: Strategy.tasks), context: Strategy.context(at: during))
        #expect(mail.action == 0)
        #expect(mail.limits.contains(.busy))
        #expect(mail.actionFactors.gate == 0)
    }

    @Test("Важность: приоритет, тип, срок цели и её собственная важность")
    func importanceFactors() {
        let time = WowFixture.morning
        let context = Strategy.context(at: time)
        func importance(_ task: LineaTask, goals: [LineaGoal]? = nil) -> Double {
            let snapshot = PlanFixture.snapshot(tasks: [task], commitments: [], goals: goals, at: time)
            return engine.importance(of: task, at: time.now, context: PriorityContext(snapshot: snapshot, state: context.state, time: time)).score
        }
        let base = LineaTask(title: "Оплатить интернет", createdAt: WowFixture.created)
        var high = base
        high.priority = .important
        #expect(importance(high) > importance(base))

        // Обязательство важнее быта при прочих равных.
        let promise = LineaTask(title: "Отправить договор", createdAt: WowFixture.created)
        #expect(importance(promise) > importance(base))

        // Важная цель тянет сильнее средней, средняя — сильнее низкой.
        let linked = LineaTask(title: "Сделать лендинг", createdAt: WowFixture.created, goalID: WowFixture.goalMVP)
        func withGoal(_ priority: TaskPriority) -> Double {
            var goal = WowFixture.goals[0]
            goal.priority = priority
            return importance(linked, goals: [goal])
        }
        #expect(withGoal(.important) > withGoal(.normal))
        #expect(withGoal(.normal) > withGoal(.low))
    }

    @Test("Переносы и ждущие задачи поднимают важность")
    func deferralsAndDependents() {
        let time = WowFixture.morning
        let first = LineaTask(id: UUID(uuidString: "52000000-0000-0000-0000-000000000001")!, title: "Собрать данные",
                              date: WowFixture.today, createdAt: WowFixture.created, estimatedMinutes: 30)
        var slipped = first
        slipped.deferralCount = 3
        let calm = engine.importance(of: first, at: time.now, context: Strategy.context(at: time, tasks: [first]))
        let pressed = engine.importance(of: slipped, at: time.now, context: Strategy.context(at: time, tasks: [slipped]))
        #expect(pressed.factors.deferrals == 1)
        #expect(pressed.score > calm.score)

        let waiting = (0..<2).map { index in
            LineaTask(id: UUID(uuidString: "52000000-0000-0000-0000-00000000001\(index)")!, title: "Отчёт \(index)",
                      date: WowFixture.today, createdAt: WowFixture.created, blockedBy: [first.id])
        }
        let unblocks = engine.importance(of: first, at: time.now, context: Strategy.context(at: time, tasks: [first] + waiting))
        #expect(unblocks.factors.dependents == 1)
        #expect(unblocks.score > calm.score)
    }

    @Test("Ритм и баланс: та же цель — легче, третья задача быта подряд — слабее")
    func rhythmAndBalance() {
        let time = WowFixture.time(11)
        let errands = (0..<3).map { index in
            LineaTask(title: "Купить продукты \(index)", date: WowFixture.today, isDone: true,
                      createdAt: WowFixture.created, completedAt: WowFixture.moment(10, index * 10))
        }
        let next = LineaTask(title: "Оплатить интернет", date: WowFixture.today, createdAt: WowFixture.created)
        let tired = engine.assess(next, context: Strategy.context(at: time, tasks: errands + [next], commitments: []))
        #expect(tired.actionFactors.balance == 0.7)

        let goalDone = LineaTask(title: "Собрать фидбек", date: WowFixture.today, isDone: true, createdAt: WowFixture.created,
                                 goalID: WowFixture.goalMVP, completedAt: WowFixture.moment(10, 30))
        let sameGoal = LineaTask(title: "Обновить лендинг", date: WowFixture.today, createdAt: WowFixture.created,
                                 goalID: WowFixture.goalMVP)
        let flow = engine.assess(sameGoal, context: Strategy.context(at: time, tasks: [goalDone, sameGoal], commitments: []))
        #expect(flow.actionFactors.rhythm == 1)
    }

    @Test("Задача со своим временем — «сейчас» только в своё время")
    func fixedTimeGate() {
        let call = LineaTask(title: "Созвон с командой", date: WowFixture.today, createdAt: WowFixture.created,
                             scheduledStart: WowFixture.moment(17), estimatedMinutes: 30)
        let context = Strategy.context(at: WowFixture.time(15), tasks: [call], commitments: [])
        let early = engine.assess(call, at: WowFixture.moment(15), context: context)
        #expect(early.actionFactors.gate == 0)
        #expect(early.limits.contains(.fixedTime(WowFixture.moment(17))))
        let onTime = engine.assess(call, at: WowFixture.moment(16, 55), context: context)
        #expect(onTime.actionFactors.gate == 1)
    }

    @Test("Задача без дня со сроком на этой неделе — кандидат дня, без срока — нет")
    func undatedCandidates() {
        let time = WowFixture.morning
        let week = LineaTask(id: UUID(uuidString: "53000000-0000-0000-0000-000000000001")!, title: "Подготовить релиз",
                             createdAt: WowFixture.created, deadline: TaskDay.endOfWeek(time: time, profile: WowFixture.profile))
        let someday = LineaTask(id: UUID(uuidString: "53000000-0000-0000-0000-000000000002")!, title: "Разобрать шкаф",
                                createdAt: WowFixture.created)
        let ids = Set(engine.candidates(context: Strategy.context(at: time, tasks: [week, someday], commitments: [])).map(\.id))
        #expect(ids.contains(week.id))
        #expect(!ids.contains(someday.id))
    }

    // MARK: Зависимости

    @Test("Задача ждёт другую: в плане встаёт после неё, хотя важнее")
    func dependencyOrder() {
        let time = WowFixture.morning
        let data = LineaTask(id: UUID(uuidString: "54000000-0000-0000-0000-000000000001")!, title: "Собрать данные",
                             date: WowFixture.today, createdAt: WowFixture.created, estimatedMinutes: 60)
        let report = LineaTask(id: UUID(uuidString: "54000000-0000-0000-0000-000000000002")!, title: "Написать отчёт",
                               date: WowFixture.today, priority: .important, createdAt: WowFixture.created.addingTimeInterval(60),
                               estimatedMinutes: 60, blockedBy: [data.id])
        let state = PlanFixture.state(energy: 0.6, confidence: 0.8, advice: .normal, at: time)
        let plan = PlanFixture.engine().plan(
            snapshot: PlanFixture.snapshot(tasks: [data, report], commitments: [], at: time),
            state: state, time: time, planID: WowFixture.planID
        )
        let first = plan.block(for: data.id)!
        let second = plan.block(for: report.id)!
        #expect(second.start >= first.end)

        var free = report
        free.blockedBy = []
        let unconstrained = PlanFixture.engine().plan(
            snapshot: PlanFixture.snapshot(tasks: [data, free], commitments: [], at: time),
            state: state, time: time, planID: WowFixture.planID
        )
        #expect(unconstrained.block(for: report.id)!.start < unconstrained.block(for: data.id)!.start)
    }

    @Test("Задача ждёт то, что сегодня не делается, — переносится с причиной")
    func blockedIsDeferred() {
        let time = WowFixture.morning
        let later = LineaTask(id: UUID(uuidString: "55000000-0000-0000-0000-000000000001")!, title: "Получить доступы",
                              date: WowFixture.moment(0, 0, dayOffset: 3), createdAt: WowFixture.created, estimatedMinutes: 30)
        let waiting = LineaTask(id: UUID(uuidString: "55000000-0000-0000-0000-000000000002")!, title: "Настроить сервер",
                                date: WowFixture.today, createdAt: WowFixture.created, estimatedMinutes: 30, blockedBy: [later.id])
        let plan = PlanFixture.engine().plan(
            snapshot: PlanFixture.snapshot(tasks: [later, waiting], commitments: [], at: time),
            state: PlanFixture.state(energy: 0.6, confidence: 0.8, advice: .normal, at: time),
            time: time, planID: WowFixture.planID
        )
        #expect(plan.deferredTaskIDs == [waiting.id])
        #expect(plan.facts.contains(.taskDeferred(taskID: waiting.id, title: "Настроить сервер", reason: DecisionEngine.DeferReason.blocked)))
    }

    @Test("Петля зависимостей не ломает план: одно ребро выпадает, повторить петлю нельзя")
    func dependencyCycle() {
        let a = UUID(uuidString: "56000000-0000-0000-0000-000000000001")!
        let b = UUID(uuidString: "56000000-0000-0000-0000-000000000002")!
        let tasks = [
            LineaTask(id: a, title: "A", createdAt: WowFixture.created, blockedBy: [b]),
            LineaTask(id: b, title: "B", createdAt: WowFixture.created.addingTimeInterval(60), blockedBy: [a]),
        ]
        let graph = TaskDependencies(tasks: tasks)
        #expect(graph.openBlockers(of: a) == [b])
        #expect(graph.openBlockers(of: b).isEmpty)
        #expect(TaskDependencies.canBlock(b, by: a, in: [tasks[0], LineaTask(id: b, title: "B", createdAt: WowFixture.created)]) == false)
        #expect(TaskDependencies.canBlock(a, by: a, in: tasks) == false)
        // Закрытая задача уже никого не держит.
        var done = tasks
        done[1].isDone = true
        #expect(TaskDependencies(tasks: done).openBlockers(of: a).isEmpty)
    }

    // MARK: Переносы

    @Test("Перенос — это задача на сегодня или просроченная, сдвинутая позже или без дня")
    func deferralRule() {
        let time = WowFixture.morning
        let today = LineaTask(title: "Отчёт", date: WowFixture.today, createdAt: WowFixture.created)
        func moved(_ task: LineaTask, to offset: Int?) -> LineaTask {
            var copy = task
            copy.date = offset.map { WowFixture.calendar.startOfDay(for: WowFixture.moment(12, 0, dayOffset: $0)) }
            return copy
        }
        #expect(TaskDeferral.isDeferral(from: today, to: moved(today, to: 1), time: time))
        #expect(TaskDeferral.isDeferral(from: today, to: moved(today, to: nil), time: time))
        #expect(!TaskDeferral.isDeferral(from: today, to: today, time: time))
        let overdue = moved(today, to: -1)
        #expect(TaskDeferral.isDeferral(from: overdue, to: moved(today, to: 0), time: time))
        let future = moved(today, to: 3)
        #expect(!TaskDeferral.isDeferral(from: future, to: moved(today, to: 5), time: time))
        var done = today
        done.isDone = true
        #expect(!TaskDeferral.isDeferral(from: done, to: moved(done, to: 1), time: time))

        let counted = TaskDeferral.counted(previous: today, updated: moved(today, to: 1), time: time)
        #expect(counted.deferralCount == 1)
        #expect(TaskDeferral.counted(previous: counted, updated: moved(counted, to: 2), time: WowFixture.time(9, 0, dayOffset: 1)).deferralCount == 2)
    }

    // MARK: Совместимость

    @Test("Старые записи читаются: задача без переносов и зависимостей, цель без важности, план без двух оценок")
    func legacyDecoding() throws {
        func strip<T: Encodable>(_ value: T, _ keys: [String]) throws -> Data {
            var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
            for key in keys { object.removeValue(forKey: key) }
            return try JSONSerialization.data(withJSONObject: object)
        }
        let task = LineaTask(title: "Старая", createdAt: WowFixture.created, deferralCount: 2, blockedBy: [WowFixture.taskA])
        let oldTask = try JSONDecoder().decode(LineaTask.self, from: strip(task, ["deferralCount", "blockedBy", "kindOverride"]))
        #expect(oldTask.deferralCount == 0)
        #expect(oldTask.blockedBy.isEmpty)
        let roundTrip = try JSONDecoder().decode(LineaTask.self, from: JSONEncoder().encode(task))
        #expect(roundTrip == task)

        let goal = LineaGoal(title: "Цель", createdAt: WowFixture.created, priority: .important)
        let oldGoal = try JSONDecoder().decode(LineaGoal.self, from: strip(goal, ["priority"]))
        #expect(oldGoal.priority == .normal)
        #expect(try JSONDecoder().decode(LineaGoal.self, from: JSONEncoder().encode(goal)) == goal)

        let score = ScoreBreakdown(urgency: 0.5, importance: 0.5, goalAlignment: 0, energyFit: nil, durationFit: 1, total: 0.4,
                                   importanceScore: 0.6, actionScore: 0.7)
        let oldScore = try JSONDecoder().decode(ScoreBreakdown.self, from: strip(score, ["importanceScore", "actionScore"]))
        #expect(oldScore.importanceScore == nil)
        #expect(oldScore.total == 0.4)
    }
}

@Suite("Сейчас")
struct NextActionTests {
    private let useCase = NextActionUseCase(renderer: RuleBasedExplainer())

    private func run(at time: TimeContext, tasks: [LineaTask] = Strategy.tasks, record: DayRecord? = nil, preferred: UUID? = nil) -> NextAction? {
        useCase.run(record: record ?? Strategy.record(at: time, tasks: tasks), tasks: tasks, calibration: .default,
                    time: time, preferred: preferred)
    }

    /// Пять коротких задач на сегодня — есть из чего выбрать.
    private var errands: [LineaTask] {
        ["Ответить клиенту", "Проверить сборку", "Разобрать письмо", "Оплатить интернет", "Купить продукты"].enumerated().map { index, title in
            LineaTask(id: UUID(uuidString: "57000000-0000-0000-0000-00000000000\(index)")!, title: title, date: WowFixture.today,
                      priority: index == 0 ? .important : .normal,
                      createdAt: WowFixture.created.addingTimeInterval(TimeInterval(index * 60)), estimatedMinutes: 15)
        }
    }

    @Test("За 20 минут до встречи: короткое дело сейчас, стратегия — после встречи")
    func shortWindowSuggestsQuickTask() throws {
        let action = try #require(run(at: WowFixture.time(15, 30)))
        #expect(action.taskID == Strategy.mail)
        #expect(action.option?.title == "Ответить на письма")
        #expect(action.option?.minutes == 15)
        #expect(action.laterTaskID == Strategy.strategy)
        #expect(action.headline == "Сейчас — «Ответить на письма».")
        #expect(action.reason == "До встречи осталось 20 мин. «Подготовить стратегию» лучше после встречи: на неё нужно 1 ч 30 мин.")
        // Стратегия сейчас не помещается — в «Другое» её нет.
        #expect(action.alternatives.isEmpty)
    }

    @Test("После встречи стратегия снова «сейчас»; длинное окно не упоминается")
    func afterMeetingStrategyIsBack() throws {
        let action = try #require(run(at: WowFixture.time(16, 20)))
        #expect(action.taskID == Strategy.strategy)
        #expect(action.laterTaskID == nil)
        #expect(action.reason == "")
        #expect(action.alternatives.map(\.taskID) == [Strategy.mail])
    }

    @Test("Окно меньше двух часов — Linea о нём напоминает")
    func shortRemainderIsMentioned() throws {
        let action = try #require(run(at: WowFixture.time(19)))
        #expect(action.taskID == Strategy.strategy)
        #expect(action.reason == "До конца рабочего дня осталось 2 ч.")
    }

    @Test("Ничего не помещается — короткая пауза, важное — после")
    func nothingFits() throws {
        let action = try #require(run(at: WowFixture.time(15, 40), tasks: [Strategy.tasks[0]]))
        #expect(action.option == nil)
        #expect(action.headline == "До встречи осталось 10 мин — короткая пауза.")
        #expect(action.reason == "«Подготовить стратегию» лучше начать после встречи.")
    }

    @Test("Во время встречи и после рабочего дня «Сейчас» молчит")
    func silentWhenBusy() {
        #expect(run(at: WowFixture.time(16, 0)) == nil)
        #expect(run(at: WowFixture.time(21, 30)) == nil)
    }

    @Test("Закрытая задача больше не «сейчас»")
    func doneTaskIsSkipped() throws {
        var tasks = Strategy.tasks
        tasks[0].isDone = true
        tasks[0].completedAt = WowFixture.moment(16, 19)
        let action = try #require(run(at: WowFixture.time(16, 20), tasks: tasks))
        #expect(action.taskID == Strategy.mail)
    }

    @Test("Принятый план — договорённость: идущий блок и есть «сейчас»")
    func acceptedPlanWins() throws {
        let time = WowFixture.time(10)
        let block = PlanBlock(id: "b", kind: .focus, taskID: Strategy.mail, title: "Ответить на письма",
                              start: WowFixture.moment(9, 50), end: WowFixture.moment(10, 20))
        let plan = DayPlan(id: WowFixture.planID, day: WowFixture.today, status: .accepted, createdAt: WowFixture.morning.now,
                           snapshotID: WowFixture.snapshotID, blocks: [block], topTaskIDs: [Strategy.mail])
        let action = try #require(run(at: time, record: Strategy.record(at: time, plan: plan)))
        #expect(action.taskID == Strategy.mail)
    }

    // MARK: Одно действие и «Другое»

    @Test("Одно действие и не больше трёх альтернатив — только то, что уместно сейчас")
    func oneActionAndAtMostThreeAlternatives() throws {
        let time = WowFixture.time(10)
        let action = try #require(run(at: time, tasks: errands))
        #expect(action.taskID == errands[0].id, "Важное и короткое — первым")
        #expect(action.alternatives.count == NextActionUseCase.maxAlternatives)
        #expect(!action.alternatives.contains { $0.taskID == action.taskID })
        #expect(action.alternatives.allSatisfy { $0.minutes == 15 })
    }

    @Test("Выбранное в «Другое» становится «сейчас»")
    func preferredAlternativeWins() throws {
        let time = WowFixture.time(10)
        let first = try #require(run(at: time, tasks: errands))
        let chosen = try #require(first.alternatives.last)
        let second = try #require(run(at: time, tasks: errands, preferred: chosen.taskID))
        #expect(second.taskID == chosen.taskID)
        #expect(second.alternatives.contains { $0.taskID == first.taskID })
    }

    // MARK: Начатое действие

    @Test("«Начать» пишет отклик в день, задача не меняется")
    func startActionRecordsFeedback() throws {
        let time = WowFixture.time(10)
        let action = try #require(run(at: time, tasks: errands))
        let option = try #require(action.option)
        let record = StartActionUseCase().run(record: Strategy.record(at: time, tasks: errands), option: option,
                                              wasAlternative: false, time: time)
        let started = record.feedback.compactMap { item -> ActionStart? in
            if case .actionStarted(let start) = item.kind { return start }
            return nil
        }
        #expect(started == [ActionStart(taskID: option.taskID, minutes: 15, wasAlternative: false)])
    }

    @Test("Начатое действие — «в работе», пока не закрыто и не вышло время")
    func startedActionIsShown() throws {
        let start = WowFixture.time(10)
        let option = NextAction.Option(taskID: errands[1].id, title: "Проверить сборку", minutes: 15)
        let record = StartActionUseCase().run(record: Strategy.record(at: start, tasks: errands), option: option,
                                              wasAlternative: true, time: start)

        let during = try #require(run(at: WowFixture.time(10, 10), tasks: errands, record: record))
        #expect(during.taskID == option.taskID)
        #expect(during.isStarted)
        #expect(during.startedAt == WowFixture.moment(10))
        #expect(during.reason == "Начато в 10:00.")
        #expect(!during.alternatives.contains { $0.taskID == option.taskID })
        #expect(during.alternatives.count == NextActionUseCase.maxAlternatives)

        // 15 минут отведено: действие живёт до 30 минут, потом — снова выбор.
        #expect(record.activeAction(tasks: errands, at: WowFixture.moment(10, 29)) != nil)
        #expect(record.activeAction(tasks: errands, at: WowFixture.moment(10, 31)) == nil)
        // Задачу закрыли — действие кончилось.
        var done = errands
        done[1].isDone = true
        #expect(record.activeAction(tasks: done, at: WowFixture.moment(10, 5)) == nil)
    }

    @Test("План держит время начатого действия занятым")
    func startedActionHoldsItsTime() async throws {
        let time = WowFixture.time(10)
        let option = NextAction.Option(taskID: errands[2].id, title: "Разобрать письмо", minutes: 15)
        let record = StartActionUseCase().run(record: DayRecord(day: WowFixture.today, updatedAt: time.now),
                                              option: option, wasAlternative: false, time: time)
        let planDay = PlanDayUseCase(
            contextEngine: ContextEngine(providers: []),
            decisionEngine: PlanFixture.engine(),
            nudgeEngine: PlanFixture.nudgeEngine(),
            explainer: RuleBasedExplainer()
        )
        let output = await planDay.run(PlanDayUseCase.Input(
            time: WowFixture.time(10, 5), tasks: errands, goals: [], existing: record, allowsRemoteExplanation: false
        ))
        let plan = try #require(output.record.plan)
        let held = try #require(plan.blocks.first { $0.taskID == option.taskID })
        #expect(held.kind == .commitment)
        #expect(held.start == WowFixture.moment(10))
        #expect(held.end == WowFixture.moment(10, 15))
        #expect(!plan.blocks.contains { $0.kind == .focus && $0.start < WowFixture.moment(10, 15) })
    }

    @Test("Встреча и созвон с назначенным временем — встреча")
    func meetingKind() {
        #expect(CommitmentKind.inferred(fromTitle: "Встреча с клиентом", default: .task) == .meeting)
        #expect(CommitmentKind.inferred(fromTitle: "Созвон с командой", default: .task) == .meeting)
        #expect(CommitmentKind.inferred(fromTitle: "Тренировка", default: .task) == .workout)
        #expect(CommitmentKind.inferred(fromTitle: "Забрать посылку", default: .task) == .task)
    }
}
