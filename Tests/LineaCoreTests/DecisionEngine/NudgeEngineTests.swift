import Testing
import Foundation
@testable import LineaCore

@Suite("Напоминания")
struct NudgeEngineTests {
    private let engine = NudgeEngine(renderer: StubRenderer())

    /// An accepted plan for the wow-scenario day.
    private func acceptedPlan(at time: TimeContext = WowFixture.morning) -> DayPlan {
        var plan = PlanFixture.engine().plan(
            snapshot: WowFixture.snapshot(at: time),
            state: PlanFixture.reducedState(at: time),
            time: time, planID: WowFixture.planID
        )
        plan.status = .accepted
        plan.acceptedAt = time.now
        return plan
    }

    private func context(
        at time: TimeContext,
        tasks: [LineaTask] = WowFixture.tasks,
        feedback: [UserFeedback] = [],
        existing: [Nudge] = [],
        calibration: Calibration = .default,
        profile: UserProfile = .default
    ) -> NudgeContext {
        var snapshot = WowFixture.snapshot(at: time)
        snapshot.tasks = tasks
        snapshot.profile = profile
        return NudgeContext(
            plan: acceptedPlan(), snapshot: snapshot, state: PlanFixture.reducedState(at: time),
            feedback: feedback, existing: existing, calibration: calibration,
            config: .default, time: time
        )
    }

    @Test("В 14:30 напоминание про незакрытую задачу с двумя ответами")
    func afternoon() throws {
        let due = engine.due(context(at: WowFixture.afternoon))
        let nudge = try #require(due.first)
        #expect(nudge.kind == .behindSchedule)
        #expect(nudge.taskID != nil)
        #expect(nudge.actions.count >= 1)
        #expect(nudge.cancelWhen.contains(.taskDone(nudge.taskID!)))
    }

    @Test("Ранним утром напоминаний ещё нет")
    func tooEarly() {
        #expect(engine.due(context(at: WowFixture.time(9, 30))).isEmpty)
    }

    @Test("Выполненные задачи снимают напоминание")
    func doneTasks() {
        var tasks = WowFixture.tasks
        for index in tasks.indices { tasks[index].isDone = true }
        #expect(engine.due(context(at: WowFixture.afternoon, tasks: tasks)).isEmpty)
    }

    @Test("В тихие часы Linea молчит")
    func quietHours() {
        let night = WowFixture.time(23, 30)
        #expect(engine.nudges(context(at: night)).allSatisfy { $0.kind != .behindSchedule })
    }

    @Test("Вечером появляется вопрос о дне, а после оценки исчезает")
    func eveningCheckIn() {
        let evening = WowFixture.time(20, 45)
        #expect(engine.nudges(context(at: evening)).contains { $0.kind == .eveningCheckIn })

        let rated = UserFeedback(at: evening.now, kind: .dayRating(.ok))
        #expect(!engine.nudges(context(at: evening, feedback: [rated])).contains { $0.kind == .eveningCheckIn })
    }

    @Test("Уже запланированное напоминание не дублируется")
    func noDuplicates() throws {
        let base = context(at: WowFixture.afternoon)
        let first = try #require(engine.nudges(base).first)
        let again = engine.nudges(context(at: WowFixture.afternoon, existing: [first]))
        #expect(!again.contains { $0.id == first.id })
    }

    @Test("Число напоминаний за день ограничено")
    func dailyLimit() {
        let nudges = engine.nudges(context(at: WowFixture.afternoon))
        #expect(nudges.count <= EngineConfig.default.maxNudgesPerDay)
    }

    @Test("Напоминания идут по времени")
    func chronological() {
        let nudges = engine.nudges(context(at: WowFixture.afternoon))
        #expect(nudges == nudges.sorted { $0.fireAt < $1.fireAt })
    }

    @Test("Текст пишет рендерер, а не движок")
    func textComesFromRenderer() throws {
        let nudge = try #require(engine.due(context(at: WowFixture.afternoon)).first)
        #expect(nudge.title.hasPrefix("headline:"))
    }
}
