import Testing
import Foundation
@testable import LineaCore

@Suite("Калибровка по оценкам дня")
struct FeedbackEngineTests {
    private let engine = FeedbackEngine()
    private let time = WowFixture.evening

    /// A day with a state, a plan and an evening rating.
    private func day(
        offset: Int,
        rating: DayRating,
        energy: Double,
        advice: LoadAdvice,
        confidence: Double = 0.9,
        plannedMinutes: Int = 120
    ) -> DayRecord {
        let day = WowFixture.calendar.date(byAdding: .day, value: offset, to: WowFixture.today)!
        let state = UserState(
            day: day, computedAt: day, components: [],
            energy: energy, confidence: confidence, loadAdvice: advice
        )
        let block = PlanBlock(
            id: "b-\(offset)", kind: .focus, taskID: WowFixture.taskA, title: "Задача",
            start: day.addingTimeInterval(9 * 3600),
            end: day.addingTimeInterval(9 * 3600 + Double(plannedMinutes) * 60)
        )
        let plan = DayPlan(
            id: DeterministicID.planID(day: day, time: time), day: day, status: .accepted,
            createdAt: day, snapshotID: WowFixture.snapshotID, blocks: [block], topTaskIDs: [WowFixture.taskA]
        )
        let feedback = UserFeedback(at: day.addingTimeInterval(21 * 3600), kind: .dayRating(rating), energy: energy, energyConfidence: confidence, loadAdvice: advice)
        return DayRecord(day: day, state: state, plan: plan, feedback: [feedback], updatedAt: day)
    }

    @Test("«Тяжело» на бодрых днях снижает оценку сил")
    func energyBias() {
        let history = (1...3).map { day(offset: -$0, rating: .hard, energy: 0.7, advice: .normal) }
        let result = engine.calibrate(history: history, previous: .default, time: time)
        #expect(result.energyBias < 0)
        #expect(result.energyBias >= -0.15)
        #expect(result.ratingsCount == 3)
    }

    @Test("Пересчёт от той же истории не сдвигает калибровку")
    func idempotent() {
        let history = (1...4).map { day(offset: -$0, rating: .hard, energy: 0.7, advice: .normal) }
        let once = engine.calibrate(history: history, previous: .default, time: time)
        let twice = engine.calibrate(history: history, previous: once, time: time)
        #expect(once.energyBias == twice.energyBias)
        #expect(once.reduceThreshold == twice.reduceThreshold)
        #expect(once.capacityFactor == twice.capacityFactor)
    }

    @Test("Дважды «Тяжело» при «можно больше» поднимает порог")
    func pushThreshold() {
        let history = [
            day(offset: -3, rating: .hard, energy: 0.8, advice: .push),
            day(offset: -2, rating: .ok, energy: 0.8, advice: .push),
            day(offset: -1, rating: .hard, energy: 0.8, advice: .push),
        ]
        let result = engine.calibrate(history: history, previous: .default, time: time)
        #expect(abs(result.pushThreshold - 0.73) < 1e-9)
    }

    @Test("Один тяжёлый день ничего не меняет")
    func singleDayIsNotAPattern() {
        let result = engine.calibrate(history: [day(offset: -1, rating: .hard, energy: 0.8, advice: .push)], previous: .default, time: time)
        #expect(result.pushThreshold == Calibration.default.pushThreshold)
    }

    @Test("«Отлично» на разгруженных днях опускает порог разгрузки")
    func reduceThreshold() {
        let history = (1...2).map { day(offset: -$0, rating: .great, energy: 0.3, advice: .reduce) }
        let result = engine.calibrate(history: history, previous: .default, time: time)
        #expect(abs(result.reduceThreshold - 0.37) < 1e-9)
    }

    @Test("Неуверенное состояние не калибрует")
    func lowConfidenceIsIgnored() {
        let history = (1...3).map { day(offset: -$0, rating: .hard, energy: 0.7, advice: .normal, confidence: 0.2) }
        #expect(engine.calibrate(history: history, previous: .default, time: time).energyBias == 0)
    }

    @Test("Тяжёлые дни ужимают ёмкость дня")
    func capacityFactor() {
        let history = (1...3).map { day(offset: -$0, rating: .hard, energy: 0.5, advice: .normal) }
        let result = engine.calibrate(history: history, previous: .default, time: time)
        #expect(result.capacityFactor < 1)
        #expect(result.capacityFactor >= 0.5)
    }

    @Test("Постоянные переносы удлиняют паузу перед напоминанием")
    func nudgeGrace() {
        var record = day(offset: -1, rating: .ok, energy: 0.5, advice: .normal)
        record.feedback += (1...3).map {
            UserFeedback(at: record.day.addingTimeInterval(Double($0) * 3600),
                         kind: .nudgeResponse(nudgeID: "n\($0)", response: .deferred))
        }
        let result = engine.calibrate(history: [record], previous: .default, time: time)
        #expect(result.nudgeGraceMinutes == 30)
    }

    @Test("Два отказа подряд заставляют напоминать реже")
    func nudgeCooldown() {
        var record = day(offset: -1, rating: .ok, energy: 0.5, advice: .normal)
        record.feedback += (1...2).map {
            UserFeedback(at: record.day.addingTimeInterval(Double($0) * 3600),
                         kind: .nudgeResponse(nudgeID: "n\($0)", response: .dismissed))
        }
        #expect(engine.calibrate(history: [record], previous: .default, time: time).nudgeCooldownMultiplier == 2)
    }

    @Test("Пустая история оставляет значения по умолчанию")
    func emptyHistory() {
        let result = engine.calibrate(history: [], previous: .default, time: time)
        #expect(result.energyBias == 0)
        #expect(result.reduceThreshold == Calibration.default.reduceThreshold)
        #expect(result.ratingsCount == 0)
        #expect(result.changeLog.isEmpty)
    }

    @Test("Каждое изменение попадает в журнал")
    func changeLog() {
        let history = (1...3).map { day(offset: -$0, rating: .hard, energy: 0.7, advice: .normal) }
        let result = engine.calibrate(history: history, previous: .default, time: time)
        #expect(!result.changeLog.isEmpty)
        #expect(result.changeLog.contains { $0.parameter == "energyBias" })
    }
}
