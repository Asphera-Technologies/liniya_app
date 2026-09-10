import Testing
import Foundation
@testable import LineaCore

@Suite("Codable round-trips (JSON blobs in SwiftData)")
struct CodableTests {
    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    @Test("ContextSnapshot survives a JSON round-trip, including dictionary keys")
    func snapshot() throws {
        let original = WowFixture.snapshot()
        let decoded = try roundTrip(original)
        #expect(decoded.id == original.id)
        #expect(decoded.signals.count == original.signals.count)
        #expect(decoded.providerStatuses[.healthKit] == .ready)
        #expect(decoded.tasks.map(\.id) == original.tasks.map(\.id))
        #expect(decoded.commitments.map(\.id) == original.commitments.map(\.id))
        #expect(decoded.nutrition?.preferredProducts == ["овсянка", "курица", "овощи", "рыба"])
    }

    @Test("DailyHealthSummary encodes SignalKind keys as a JSON object")
    func summaryKeys() throws {
        let summary = WowFixture.history.last!
        let data = try JSONEncoder().encode(summary)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"health.sleep.asleep\""))
        let decoded = try JSONDecoder().decode(DailyHealthSummary.self, from: data)
        #expect(decoded[.sleepAsleep] == summary[.sleepAsleep])
    }

    @Test("DayRecord with plan, nudges, feedback and facts round-trips")
    func dayRecord() throws {
        let a = WowFixture.taskA
        let block = PlanBlock(id: "b1", kind: .focus, taskID: a, title: "Презентация КП",
                              start: WowFixture.moment(9), end: WowFixture.moment(10, 30),
                              score: ScoreBreakdown(urgency: 0.9, importance: 1, goalAlignment: 0.9, energyFit: 0.5, durationFit: 1, total: 0.85),
                              isTop: true, facts: [.taskPlanned(taskID: a, title: "Презентация КП", start: WowFixture.moment(9), end: WowFixture.moment(10, 30))])
        let plan = DayPlan(id: WowFixture.planID, day: WowFixture.today, createdAt: WowFixture.morning.now, snapshotID: WowFixture.snapshotID,
                           blocks: [block], topTaskIDs: [a],
                           recommendations: [Recommendation(id: "brief", kind: .dayBrief, message: "Доброе утро.", facts: [.loadAdvice(.reduce), .hardWorkDeadline(WowFixture.moment(12))], actions: [.acceptPlan])],
                           facts: [.topTaskCount(3)])
        let nudge = Nudge(id: "n1", kind: .behindSchedule, fireAt: WowFixture.afternoon.now, taskID: a, title: "План", body: "…",
                          actions: [.finishNow(taskID: a), .deferTask(taskID: a)], cancelWhen: [.taskDone(a)],
                          facts: [.nextCommitment(title: "Созвон", at: WowFixture.moment(15, 50), minutesLeft: 80)])
        let feedback = UserFeedback(at: WowFixture.evening.now, kind: .dayRating(.hard), energy: 0.38, energyConfidence: 0.9, loadAdvice: .reduce, planID: plan.id)
        let state = UserState(day: WowFixture.today, computedAt: WowFixture.morning.now,
                              components: [StateComponent(kind: .sleep, score: 0.6, confidence: 1, z: -2.1, level: .belowUsual, facts: [.sleepDuration(seconds: 21_780)])],
                              energy: 0.38, confidence: 0.9, loadAdvice: .reduce, baselineProgress: BaselineProgress(days: 28, needed: 7), facts: [.loadAdvice(.reduce)])
        let record = DayRecord(day: WowFixture.today, snapshot: WowFixture.snapshot(), state: state, plan: plan, nudges: [nudge], feedback: [feedback], updatedAt: WowFixture.evening.now)

        let decoded = try roundTrip(record)
        #expect(decoded.plan?.blocks.first?.score?.total == 0.85)
        #expect(decoded.plan?.recommendations.first?.facts == [.loadAdvice(.reduce), .hardWorkDeadline(WowFixture.moment(12))])
        #expect(decoded.nudges.first?.actions == [.finishNow(taskID: a), .deferTask(taskID: a)])
        #expect(decoded.rating == .hard)
        #expect(decoded.state?.component(.sleep)?.level == .belowUsual)
        #expect(decoded.state?.facts == [.loadAdvice(.reduce)])
    }

    @Test("Calibration and profiles round-trip")
    func smallDocuments() throws {
        var calibration = Calibration()
        calibration.energyBias = -0.05
        calibration.changeLog = [CalibrationChange(at: WowFixture.evening.now, parameter: "energyBias", from: 0, to: -0.05, reason: "hard day")]
        #expect(try roundTrip(calibration) == calibration)
        #expect(try roundTrip(WowFixture.profile) == WowFixture.profile)
        #expect(try roundTrip(WowFixture.nutrition) == WowFixture.nutrition)
    }
}
