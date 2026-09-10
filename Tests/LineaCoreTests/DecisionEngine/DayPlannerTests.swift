import Testing
import Foundation
@testable import LineaCore

@Suite("DecisionEngine")
struct DayPlannerTests {

    // MARK: - Wow-сценарий

    @Test("Утро wow-сценария: порядок блоков, обязательства на месте, пересечений нет")
    func wowTimeline() {
        let time = WowFixture.morning
        let plan = PlanFixture.engine().plan(
            snapshot: WowFixture.snapshot(at: time), state: PlanFixture.reducedState(at: time),
            time: time, planID: WowFixture.planID
        )

        #expect(PlanFixture.timeline(plan) == [
            "09:00–10:30 focus Презентация КП",
            "10:40–11:10 focus Ответить на письма",
            "13:00–13:40 meal Обед",
            "13:40–15:40 focus Разработка Linea",
            "15:50–16:20 commitment Созвон с командой",
            "17:00–18:00 commitment Тренировка",
        ])
        #expect(PlanFixture.overlaps(plan.blocks) == false)
        #expect(plan.deferredTaskIDs.isEmpty)
        #expect(plan.focusBlocks.allSatisfy { $0.score != nil })
    }

    @Test("Обед и тренировка дают факты mealWindow и workoutPlanned")
    func commitmentFacts() {
        let time = WowFixture.morning
        let plan = PlanFixture.engine().plan(
            snapshot: WowFixture.snapshot(at: time), state: PlanFixture.reducedState(at: time),
            time: time, planID: WowFixture.planID
        )

        let meal = PlanFixture.mealWindow(plan.facts)
        #expect(meal?.kind == .lunch)
        #expect(meal?.start == WowFixture.moment(13))
        #expect(meal?.end == WowFixture.moment(13, 40))
        #expect(PlanFixture.workoutPlanned(plan.facts) == WowFixture.moment(17))
        #expect(PlanFixture.plannedTaskIDs(plan.facts) == [WowFixture.taskA, WowFixture.taskC, WowFixture.taskB])
    }

    @Test("Top-3 — это A, B, C, и самая сложная работа умещается до 12:00")
    func topAndHardWorkDeadline() {
        let time = WowFixture.morning
        let plan = PlanFixture.engine().plan(
            snapshot: WowFixture.snapshot(at: time), state: PlanFixture.reducedState(at: time),
            time: time, planID: WowFixture.planID
        )

        #expect(Set(plan.topTaskIDs) == [WowFixture.taskA, WowFixture.taskB, WowFixture.taskC])
        #expect(plan.topTaskIDs.first == WowFixture.taskA)
        #expect(PlanFixture.topTaskCount(plan.facts) == 3)
        #expect(PlanFixture.hardWorkDeadline(plan.facts) == WowFixture.moment(12))

        let hardest = plan.block(for: WowFixture.taskA)
        #expect(hardest?.end == WowFixture.moment(10, 30))
        #expect(plan.blocks.filter(\.isTop).map(\.taskID).compactMap { $0 }.count == 3)
    }

    @Test("LoadAdjustmentRule добавляет рекомендацию с фактами сна и восстановления")
    func loadAdjustment() {
        let time = WowFixture.morning
        let plan = PlanFixture.engine().plan(
            snapshot: WowFixture.snapshot(at: time), state: PlanFixture.reducedState(at: time),
            time: time, planID: WowFixture.planID
        )

        #expect(plan.recommendations.count == 1)
        let recommendation = plan.recommendations[0]
        #expect(recommendation.kind == .loadAdjustment)
        #expect(recommendation.priority == 10)
        #expect(recommendation.facts.contains(.loadAdvice(.reduce)))
        #expect(recommendation.facts.contains(.sleepDuration(seconds: 21_780)))
        #expect(recommendation.facts.contains(.recovery(level: .belowUsual)))
        // Текст пришёл от рендерера, движок его не сочинял.
        #expect(recommendation.title == "headline:loadAdjustment")

        let normal = PlanFixture.engine().plan(
            snapshot: WowFixture.snapshot(at: time),
            state: PlanFixture.state(energy: 0.6, confidence: 0.8, advice: .normal, at: time),
            time: time, planID: WowFixture.planID
        )
        #expect(normal.recommendations.isEmpty)
    }

    // MARK: - Детерминизм

    @Test("Два вызова plan дают одинаковые блоки")
    func deterministic() {
        let time = WowFixture.morning
        let engine = PlanFixture.engine()
        let snapshot = WowFixture.snapshot(at: time)
        let state = PlanFixture.reducedState(at: time)

        let first = engine.plan(snapshot: snapshot, state: state, time: time, planID: WowFixture.planID)
        let second = engine.plan(snapshot: snapshot, state: state, time: time, planID: WowFixture.planID)

        #expect(PlanFixture.identity(first) == PlanFixture.identity(second))
        #expect(first.topTaskIDs == second.topTaskIDs)
        #expect(first.deferredTaskIDs == second.deferredTaskIDs)
    }

    @Test("Без данных о состоянии energyFit пустой, но план строится и воспроизводится")
    func unknownState() {
        let time = WowFixture.morning
        let engine = PlanFixture.engine()
        let snapshot = WowFixture.snapshot(at: time)
        let state = PlanFixture.unknownState(at: time)

        let plan = engine.plan(snapshot: snapshot, state: state, time: time, planID: WowFixture.planID)
        let again = engine.plan(snapshot: snapshot, state: state, time: time, planID: WowFixture.planID)

        #expect(!plan.focusBlocks.isEmpty)
        #expect(plan.focusBlocks.allSatisfy { $0.score?.energyFit == nil })
        #expect(PlanFixture.identity(plan) == PlanFixture.identity(again))
        #expect(PlanFixture.overlaps(plan.blocks) == false)
    }

    // MARK: - Ограничения

    @Test("Перегруз: часть задач уходит в deferred, focus-минуты не превышают лимит .reduce")
    func overload() {
        let time = WowFixture.morning
        let tasks = (0..<8).map { index in
            LineaTask(
                id: UUID(uuidString: "F0000000-0000-0000-0000-00000000000\(index)")!,
                title: "Задача \(index)", date: WowFixture.today,
                createdAt: WowFixture.created.addingTimeInterval(TimeInterval(index * 60)),
                estimatedMinutes: 90, cognitiveDemand: .normal
            )
        }
        let snapshot = PlanFixture.snapshot(tasks: tasks, at: time)
        let plan = PlanFixture.engine().plan(
            snapshot: snapshot, state: PlanFixture.reducedState(at: time),
            time: time, planID: WowFixture.planID
        )

        let windows = FreeWindows.compute(day: WowFixture.today, now: time.now, profile: WowFixture.profile,
                                          commitments: WowFixture.defaultCommitments, time: time)
        let available = windows.reduce(0.0) { $0 + $1.duration / 60 }
        let cap = Int((available * EngineConfig.default.loadCapReduced).rounded(.down))

        let focusMinutes = plan.focusBlocks.reduce(0) { $0 + $1.durationMinutes }
        #expect(focusMinutes <= cap)
        #expect(!plan.deferredTaskIDs.isEmpty)
        #expect(plan.focusBlocks.count + plan.deferredTaskIDs.count == tasks.count)
        #expect(PlanFixture.deferredFactIDs(plan.facts) == plan.deferredTaskIDs)
        #expect(PlanFixture.overlaps(plan.blocks) == false)
    }

    @Test("При .reduce две deep-задачи разделены 60 минутами и не начинаются после 16:00")
    func deepSeparation() {
        let time = WowFixture.morning
        let tasks = (0..<3).map { index in
            LineaTask(
                id: UUID(uuidString: "D0000000-0000-0000-0000-00000000000\(index)")!,
                title: "Глубокая \(index)", date: WowFixture.today,
                createdAt: WowFixture.created.addingTimeInterval(TimeInterval(index * 60)),
                estimatedMinutes: 60, cognitiveDemand: .deep
            )
        }
        let snapshot = PlanFixture.snapshot(tasks: tasks, at: time)
        let plan = PlanFixture.engine().plan(
            snapshot: snapshot, state: PlanFixture.reducedState(at: time),
            time: time, planID: WowFixture.planID
        )

        let deep = plan.focusBlocks.sorted { $0.start < $1.start }
        #expect(deep.count >= 2)
        for index in deep.indices.dropFirst() {
            let gap = deep[index].start.timeIntervalSince(deep[index - 1].end) / 60
            #expect(gap >= 60)
        }
        #expect(deep.allSatisfy { time.hourFraction(of: $0.start) < 16 })
        #expect(!plan.deferredTaskIDs.isEmpty)
    }

    @Test("Wow-сценарий соблюдает те же правила: A утром, B после обеда, между ними не-deep время")
    func wowDeepRules() {
        let time = WowFixture.morning
        let plan = PlanFixture.engine().plan(
            snapshot: WowFixture.snapshot(at: time), state: PlanFixture.reducedState(at: time),
            time: time, planID: WowFixture.planID
        )
        let a = plan.block(for: WowFixture.taskA)!
        let b = plan.block(for: WowFixture.taskB)!
        #expect(b.start.timeIntervalSince(a.end) / 60 >= 60)
        #expect(time.hourFraction(of: b.start) < 16)
    }

    // MARK: - Пересчёт

    @Test("Replan от 14:30: прошедшее сохранено, будущее пересчитано, version = 2, статус тот же")
    func replan() {
        let morning = WowFixture.morning
        let engine = PlanFixture.engine()
        var accepted = engine.plan(
            snapshot: WowFixture.snapshot(at: morning), state: PlanFixture.reducedState(at: morning),
            time: morning, planID: WowFixture.planID
        )
        accepted.status = .accepted
        accepted.acceptedAt = morning.now

        let afternoon = WowFixture.afternoon
        let replanned = engine.replan(
            accepted, snapshot: WowFixture.snapshot(at: afternoon),
            state: PlanFixture.reducedState(at: afternoon), time: afternoon
        )

        #expect(replanned.version == 2)
        #expect(replanned.status == .accepted)
        #expect(replanned.acceptedAt == morning.now)
        #expect(replanned.id == accepted.id)

        // Всё, что закончилось до 14:30, перенесено байт-в-байт.
        let past = accepted.blocks.filter { $0.end <= afternoon.now }
        #expect(past.count == 3)
        for block in past {
            let kept = replanned.blocks.first { $0.id == block.id }
            #expect(kept?.start == block.start)
            #expect(kept?.end == block.end)
        }
        // Будущие обязательства пересобраны и не задвоились.
        #expect(Set(replanned.blocks.map(\.id)).count == replanned.blocks.count)
        #expect(replanned.blocks.contains { $0.taskID == WowFixture.taskCall && $0.kind == .commitment })
        #expect(PlanFixture.overlaps(replanned.blocks) == false)
        // Идущий блок «Разработка Linea» пересчитан: до 16:00 он уже не влезает.
        #expect(replanned.deferredTaskIDs.contains(WowFixture.taskB))
    }

    @Test("Replan сохраняет закреплённые и выполненные блоки")
    func replanKeepsPinnedAndDone() {
        let morning = WowFixture.morning
        let engine = PlanFixture.engine()
        var accepted = engine.plan(
            snapshot: WowFixture.snapshot(at: morning), state: PlanFixture.reducedState(at: morning),
            time: morning, planID: WowFixture.planID
        )
        accepted.status = .accepted
        if let index = accepted.blocks.firstIndex(where: { $0.taskID == WowFixture.taskB }) {
            accepted.blocks[index].isPinned = true
        }

        let afternoon = WowFixture.afternoon
        let replanned = engine.replan(
            accepted, snapshot: WowFixture.snapshot(at: afternoon),
            state: PlanFixture.reducedState(at: afternoon), time: afternoon
        )

        let pinned = replanned.block(for: WowFixture.taskB)
        #expect(pinned?.start == WowFixture.moment(13, 40))
        #expect(pinned?.end == WowFixture.moment(15, 40))
        #expect(replanned.deferredTaskIDs.contains(WowFixture.taskB) == false)
    }

    // MARK: - Кандидаты

    @Test("Кандидаты: сегодня, просроченное, дедлайн ≤ +2 дня и не больше трёх бездатных из активной цели")
    func candidates() {
        let time = WowFixture.morning
        let overdue = LineaTask(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!, title: "Вчерашняя",
                                date: WowFixture.moment(9, 0, dayOffset: -1), createdAt: WowFixture.created,
                                estimatedMinutes: 30)
        let soon = LineaTask(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000002")!, title: "Дедлайн послезавтра",
                             date: WowFixture.moment(9, 0, dayOffset: 5), createdAt: WowFixture.created,
                             deadline: WowFixture.moment(18, 0, dayOffset: 2), estimatedMinutes: 30)
        let far = LineaTask(id: UUID(uuidString: "A1000000-0000-0000-0000-000000000003")!, title: "Через неделю",
                            date: WowFixture.moment(9, 0, dayOffset: 7), createdAt: WowFixture.created,
                            estimatedMinutes: 30)
        let goalTasks = (0..<4).map { index in
            LineaTask(id: UUID(uuidString: "A2000000-0000-0000-0000-00000000000\(index)")!,
                      title: "Бездатная \(index)", priority: index == 0 ? .important : .low,
                      createdAt: WowFixture.created.addingTimeInterval(TimeInterval(index)),
                      estimatedMinutes: 30, goalID: WowFixture.goalMVP)
        }
        let orphan = LineaTask(id: UUID(uuidString: "A3000000-0000-0000-0000-000000000001")!, title: "Ничья",
                               createdAt: WowFixture.created, estimatedMinutes: 30)

        let snapshot = PlanFixture.snapshot(tasks: [overdue, soon, far] + goalTasks + [orphan], commitments: [], at: time)
        let candidates = PlanFixture.engine().candidateTasks(
            snapshot: snapshot, state: PlanFixture.reducedState(at: time), calibration: .default, time: time
        )
        let ids = Set(candidates.map(\.id))

        #expect(ids.contains(overdue.id))
        #expect(ids.contains(soon.id))
        #expect(ids.contains(far.id) == false)
        #expect(ids.contains(orphan.id) == false)
        #expect(candidates.filter { $0.goalID == WowFixture.goalMVP && $0.date == nil }.count == 3)
    }
}
