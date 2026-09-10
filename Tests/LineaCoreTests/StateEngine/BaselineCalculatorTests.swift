//
//  BaselineCalculatorTests.swift
//  LineaCoreTests
//
//  §6 «Baseline»: what «обычно» is allowed to mean. The interesting cases are
//  the guards — too few days (no baseline at all), a perfectly regular sleeper
//  (the spread floor stops a 20-minute shortfall from becoming z = −3) and
//  today (it is the thing being compared, so it must never be part of «usual»).
//

import Testing
import Foundation
@testable import LineaCore

@Suite("BaselineCalculator")
struct BaselineCalculatorTests {
    let calculator = BaselineCalculator()
    let time = WowFixture.morning
    let config = EngineConfig.default

    @Test("The 28 days of the fixture give the usual night of 7:13")
    func sleepBaselineOfTheFixture() throws {
        let set = calculator.compute(history: WowFixture.history, config: config, time: time)
        let sleep = try #require(set[.sleepAsleep])

        #expect(sleep.median == 25_980)                 // 7:13
        #expect(sleep.sampleCount == 28)
        #expect(sleep.isReliable)
        #expect(sleep.confidence == 1.0)
        #expect(sleep.windowDays == 28)
        #expect(sleep.spread == 1800)                   // 1.4826 · MAD(600) = 889 s → floor wins
    }

    @Test("Recovery baselines: HRV 52 ms (as ln), resting HR 54 bpm")
    func recoveryBaselines() throws {
        let set = calculator.compute(history: WowFixture.history, config: config, time: time)

        let hrv = try #require(set[.hrvLog])
        #expect(abs(hrv.median - log(52)) < 1e-12)
        #expect(hrv.spread == 0.10)                     // floor: MAD gives 0.089
        #expect(hrv.sampleCount == 28)

        let rhr = try #require(set[.restingHeartRate])
        #expect(rhr.median == 54)
        #expect(rhr.spread == 2)                        // floor: MAD gives 1.48
        #expect(rhr.isReliable)

        // Workouts happen every third day only — fewer samples, still reliable.
        let workouts = try #require(set[.workoutMinutes])
        #expect(workouts.median == 45)
        #expect(workouts.sampleCount == 9)
        #expect(workouts.spread == 15)
    }

    @Test("Fewer than three days → no baseline at all")
    func tooFewDays() {
        let short = Array(WowFixture.history.suffix(2))
        let set = calculator.compute(history: short, config: config, time: time)

        #expect(set[.sleepAsleep] == nil)
        #expect(set.baselines.isEmpty)
        #expect(calculator.baseline(kind: .sleepAsleep, values: [25_980, 26_000], windowDays: 28) == nil)
    }

    @Test("Three days are enough for a baseline, but not for «обычно»")
    func minimumDays() throws {
        let short = Array(WowFixture.history.suffix(3))
        let set = calculator.compute(history: short, config: config, time: time)
        let sleep = try #require(set[.sleepAsleep])

        #expect(sleep.sampleCount == 3)
        #expect(sleep.isReliable == false)
        #expect(sleep.confidence == 0)                  // the (n − 3) / 8 ramp starts here
    }

    @Test("A perfectly regular sleeper still gets the floor as spread")
    func spreadFloor() throws {
        let identical = Array(repeating: 25_980.0, count: 10)
        let sleep = try #require(calculator.baseline(kind: .sleepAsleep, values: identical, windowDays: 28))

        #expect(sleep.spread == 1800)                   // MAD = 0 → floor
        #expect(sleep.z(25_980 - 20 * 60) == -20.0 * 60 / 1800)   // 20 min short is −0.67, not −3

        let hrv = try #require(calculator.baseline(kind: .hrvLog, values: Array(repeating: log(52), count: 10), windowDays: 28))
        #expect(hrv.spread == 0.10)
        let unknownKind = try #require(calculator.baseline(kind: "health.custom", values: identical, windowDays: 28))
        #expect(unknownKind.spread == 0)                // no floor declared for an unknown kind
    }

    @Test("Today is compared against «usual», never part of it")
    func todayIsExcluded() throws {
        let withToday = WowFixture.history + [DailyHealthSummary(day: WowFixture.today, values: [.sleepAsleep: 3600])]
        let set = calculator.compute(history: withToday, config: config, time: time)
        let sleep = try #require(set[.sleepAsleep])

        #expect(sleep.median == 25_980)
        #expect(sleep.sampleCount == 28)

        // A day older than the window is out too.
        let old = DailyHealthSummary(day: time.adding(days: -40, to: WowFixture.today), values: [.sleepAsleep: 3600])
        let widened = calculator.compute(history: WowFixture.history + [old], config: config, time: time)
        #expect(widened[.sleepAsleep]?.sampleCount == 28)
    }

    @Test("z is clamped to ±3 so one broken night cannot dominate")
    func zIsClamped() throws {
        let sleep = try #require(calculator.compute(history: WowFixture.history, config: config, time: time)[.sleepAsleep])

        #expect(sleep.z(sleep.median) == 0)
        #expect(sleep.z(sleep.median - 1800) == -1)
        #expect(sleep.z(sleep.median - 100 * 3600) == -3)
        #expect(sleep.z(sleep.median + 100 * 3600) == 3)
        #expect(Baseline(kind: .sleepAsleep, median: 25_980, spread: 0, sampleCount: 28, windowDays: 28).z(0) == 0)
    }

    @Test("An impossible night is dropped from the baseline together with its derived values")
    func implausibleDaysAreDropped() throws {
        var history = WowFixture.history
        history[10][.sleepAsleep] = 20 * 3600
        let set = calculator.compute(history: history, config: config, time: time)

        #expect(set[.sleepAsleep]?.sampleCount == 27)
        #expect(set[.sleepInBed]?.sampleCount == 27)
        #expect(set[.sleepBedtime]?.sampleCount == 27)
        #expect(set[.restingHeartRate]?.sampleCount == 28)   // untouched by a bad night
    }
}
