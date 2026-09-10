//
//  DailySeriesBuilderTests.swift
//  LineaCoreTests
//
//  §6 «Дневные ряды» and «Валидация входов». Today's row must be built by the
//  same rules the stored history was built with — otherwise a baseline
//  compares apples with pears — and physiologically impossible samples must
//  die here, once, before any engine sees them.
//

import Testing
import Foundation
@testable import LineaCore

@Suite("DailySeriesBuilder")
struct DailySeriesBuilderTests {
    let builder = DailySeriesBuilder()
    let time = WowFixture.morning

    private func hrv(_ hour: Int, _ minute: Int, _ ms: Double) -> ContextSignal {
        ContextSignal(kind: .hrvSDNN, value: .number(ms), start: WowFixture.moment(hour, minute), source: .healthKit, unit: "ms")
    }

    private func rhr(_ hour: Int, _ bpm: Double) -> ContextSignal {
        ContextSignal(kind: .restingHeartRate, value: .number(bpm), start: WowFixture.moment(hour), source: .healthKit, unit: "bpm")
    }

    private func build(_ signals: [ContextSignal]) -> DailySeries {
        builder.build(day: WowFixture.today, signals: signals, time: time)
    }

    @Test("Today's row of the wow-scenario")
    func wowRow() throws {
        let series = build(WowFixture.healthSignals)

        #expect(series.day == WowFixture.today)
        #expect(series.sleepNight?.asleepSeconds == 21_780)
        #expect(series.summary[.sleepAsleep] == 21_780)
        #expect(series.summary[.sleepInBed] == 24_000)            // 00:40–07:20
        #expect(series.summary[.sleepBedtime] == 57)             // 00:57 as minutes since midnight
        let hrvLog = try #require(series.summary[.hrvLog])
        #expect(abs(hrvLog - log(38)) < 1e-12)
        #expect(series.summary[.restingHeartRate] == 58)
        #expect(series.summary[.steps] == 420)
        #expect(series.summary[.workoutMinutes] == nil)          // no workout today
    }

    @Test("An impossible HRV sample is dropped, the median of the rest survives")
    func outlierHRV() throws {
        let series = build(WowFixture.sleepSignalsWatch + [hrv(2, 10, 36), hrv(4, 0, 40), hrv(6, 30, 38), hrv(5, 0, 500)])

        let hrvLog = try #require(series.summary[.hrvLog])
        #expect(abs(hrvLog - log(38)) < 1e-12)
        #expect(DailySeriesBuilder.isValidHRVSample(500) == false)
        #expect(DailySeriesBuilder.isValidHRVSample(0) == false)
        #expect(DailySeriesBuilder.isValidHRVSample(300))

        // Nothing but the outlier → no HRV for the day at all.
        #expect(build([hrv(3, 0, 500)]).summary[.hrvLog] == nil)
    }

    @Test("An impossible resting heart rate is dropped")
    func outlierRestingHeartRate() {
        // The latest sample of the day wins — unless it is impossible.
        #expect(build([rhr(7, 58), rhr(9, 200)]).summary[.restingHeartRate] == 58)
        #expect(build([rhr(9, 200)]).summary[.restingHeartRate] == nil)
        #expect(build([rhr(7, 58), rhr(9, 61)]).summary[.restingHeartRate] == 61)
        #expect(DailySeriesBuilder.isValid(.restingHeartRate, 29) == false)
        #expect(DailySeriesBuilder.isValid(.restingHeartRate, 121) == false)
    }

    @Test("A 20-hour night is dropped together with everything derived from it")
    func outlierSleep() {
        let monsterNight = ContextSignal(
            kind: .sleepSegment, value: .interval(nil),
            start: WowFixture.moment(16, 0, dayOffset: -1), end: WowFixture.moment(12, 0),
            source: .healthKit,
            attributes: [SignalAttribute.stage: SleepStage.core.rawValue, SignalAttribute.sourceBundle: "com.example.tracker"]
        )
        let series = build([monsterNight] + WowFixture.hrvSignals)

        #expect(series.sleepNight == nil)
        #expect(series.summary[.sleepAsleep] == nil)
        #expect(series.summary[.sleepInBed] == nil)
        #expect(series.summary[.sleepBedtime] == nil)
        #expect(series.summary[.hrvLog] != nil)                  // the rest of the day is fine

        // The same rule applied to a stored row.
        var stored = DailyHealthSummary(day: WowFixture.today, values: [
            .sleepAsleep: 20 * 3600, .sleepInBed: 21 * 3600, .sleepBedtime: 57, .restingHeartRate: 58,
        ])
        stored = DailySeriesBuilder.validated(stored)
        #expect(stored.values == [.restingHeartRate: 58])
    }

    @Test("HRV is the ln of the NIGHT median: a daytime sample does not move it")
    func hrvUsesNightSamples() throws {
        let night = [hrv(2, 10, 36), hrv(4, 0, 40), hrv(6, 30, 38)]
        let withDaytime = build(night + [hrv(14, 0, 80)])

        let nightMedian = try #require(withDaytime.summary[.hrvLog])
        #expect(abs(nightMedian - log(38)) < 1e-12)
        // …but when the night says nothing, the whole day is used.
        let dayOnly = build([hrv(14, 0, 80), hrv(18, 0, 70)])
        let dayMedian = try #require(dayOnly.summary[.hrvLog])
        #expect(abs(dayMedian - log(75)) < 1e-12)
    }

    @Test("Steps and active energy are summed over the day")
    func cumulativeCounters() {
        let steps = [420.0, 1_500, 3_080].enumerated().map { i, v in
            ContextSignal(kind: .steps, value: .number(v), start: WowFixture.moment(8 + i), end: WowFixture.moment(9 + i), source: .healthKit, unit: "count")
        }
        let energy = [120.0, 240].enumerated().map { i, v in
            ContextSignal(kind: .activeEnergy, value: .number(v), start: WowFixture.moment(8 + i), end: WowFixture.moment(9 + i), source: .healthKit, unit: "kcal")
        }
        let series = build(steps + energy)

        #expect(series.summary[.steps] == 5_000)
        #expect(series.summary[.activeEnergy] == 360)
        // Yesterday's steps belong to yesterday's row.
        let yesterday = ContextSignal(kind: .steps, value: .number(9_000), start: WowFixture.moment(10, 0, dayOffset: -1), source: .healthKit, unit: "count")
        #expect(build(steps + [yesterday]).summary[.steps] == 5_000)
    }

    @Test("Workout minutes come from the duration of .workout signals")
    func workoutMinutes() {
        func workout(_ startHour: Int, minutes: Int) -> ContextSignal {
            ContextSignal(
                kind: .workout, value: .interval(320),
                start: WowFixture.moment(startHour), end: WowFixture.moment(startHour).addingTimeInterval(Double(minutes) * 60),
                source: .healthKit, attributes: [SignalAttribute.activity: "Бег"]
            )
        }
        let series = build([workout(7, minutes: 45), workout(19, minutes: 30)])

        #expect(series.summary[.workoutMinutes] == 75)
        #expect(build([]).summary[.workoutMinutes] == nil)
    }

    @Test("No signals at all → an empty row, not a fabricated one")
    func emptyDay() {
        let series = build([])

        #expect(series.sleepNight == nil)
        #expect(series.summary.values.isEmpty)
        #expect(series.day == WowFixture.today)
    }
}
