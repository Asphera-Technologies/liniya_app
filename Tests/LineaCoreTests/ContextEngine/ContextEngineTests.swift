import Testing
import Foundation
@testable import LineaCore

@Suite("Сбор контекста")
struct ContextEngineTests {
    private func request(_ time: TimeContext = WowFixture.morning, historyDays: Int = 0) -> ContextRequest {
        ContextRequest(day: time.dayInterval(containing: time.today), time: time, historyDays: historyDays)
    }

    private func capture(_ engine: ContextEngine, tasks: [LineaTask] = [], time: TimeContext = WowFixture.morning) async -> ContextSnapshot {
        await engine.capture(
            request: request(time), snapshotID: WowFixture.snapshotID,
            tasks: tasks, goals: WowFixture.goals, profile: WowFixture.profile,
            nutrition: WowFixture.nutrition, meals: []
        )
    }

    @Test("Отказ одного источника не мешает собрать снапшот")
    func providerFailure() async {
        let engine = ContextEngine(providers: [
            FakeContextProvider(id: .healthKit, signals: WowFixture.hrvSignals),
            FakeContextProvider(id: .nutrition, signals: [], error: .unauthorized),
        ])
        let snapshot = await capture(engine)
        #expect(snapshot.providerStatuses[.nutrition] == .unauthorized)
        #expect(snapshot.providerStatuses[.healthKit] == .ready)
        #expect(!snapshot.signals.isEmpty)
    }

    @Test("Медленный источник не задерживает утро")
    func providerTimeout() async {
        let engine = ContextEngine(
            providers: [
                FakeContextProvider(id: .healthKit, signals: WowFixture.hrvSignals),
                FakeContextProvider(id: .calendar, signals: WowFixture.healthSignals, delay: .seconds(2)),
            ],
            timeout: .milliseconds(100)
        )
        let snapshot = await capture(engine)
        #expect(snapshot.providerStatuses[.calendar] == .timedOut)
        #expect(snapshot.signals.allSatisfy { $0.source == .healthKit })
    }

    @Test("Одинаковые сигналы схлопываются, порядок не зависит от гонки")
    func deduplicationAndOrder() async {
        let doubled = WowFixture.hrvSignals + WowFixture.hrvSignals
        let a = ContextEngine(providers: [
            FakeContextProvider(id: .healthKit, signals: doubled),
            FakeContextProvider(id: .nutrition, signals: []),
        ])
        let b = ContextEngine(providers: [
            FakeContextProvider(id: .nutrition, signals: []),
            FakeContextProvider(id: .healthKit, signals: doubled),
        ])
        let first = await capture(a)
        let second = await capture(b)
        #expect(first.signals.count == WowFixture.hrvSignals.count)
        #expect(first.signals.map(\.id) == second.signals.map(\.id))
    }

    @Test("Статус есть у каждого зарегистрированного источника")
    func statusesForAll() async {
        let engine = ContextEngine(providers: [
            FakeContextProvider(id: .healthKit, signals: []),
            FakeContextProvider(id: .nutrition, signals: []),
        ])
        let snapshot = await capture(engine)
        #expect(snapshot.providerStatuses.count == 2)
        #expect(snapshot.providerStatuses[.healthKit] == .noData)
    }

    @Test("Обязательства wow-сценария собираются из питания и задач")
    func commitments() async {
        let engine = ContextEngine(providers: [
            NutritionContextProvider(profile: WowFixture.nutrition, meals: []),
        ])
        let snapshot = await capture(engine, tasks: WowFixture.tasks)
        let expected = WowFixture.defaultCommitments
        #expect(snapshot.commitments.count == expected.count)
        for (actual, wanted) in zip(snapshot.commitments, expected) {
            #expect(actual.title == wanted.title)
            #expect(actual.start == wanted.start)
            #expect(actual.end == wanted.end)
            #expect(actual.kind == wanted.kind)
        }
    }

    @Test("Выполненная задача со временем перестаёт занимать время")
    func doneTaskIsNotACommitment() async {
        var tasks = WowFixture.tasks
        if let index = tasks.firstIndex(where: { $0.id == WowFixture.taskCall }) {
            tasks[index].isDone = true
        }
        let engine = ContextEngine(providers: [NutritionContextProvider(profile: WowFixture.nutrition, meals: [])])
        let snapshot = await capture(engine, tasks: tasks)
        #expect(!snapshot.commitments.contains { $0.taskID == WowFixture.taskCall })
    }

    @Test("Тренировка распознаётся по названию")
    func workoutKind() async {
        let engine = ContextEngine(providers: [FakeContextProvider(signals: [])])
        let snapshot = await capture(engine, tasks: WowFixture.tasks)
        let workout = snapshot.commitments.first { $0.taskID == WowFixture.taskWorkout }
        #expect(workout?.kind == .workout)
        #expect(snapshot.commitments.first { $0.taskID == WowFixture.taskCall }?.kind == .task)
    }
}
