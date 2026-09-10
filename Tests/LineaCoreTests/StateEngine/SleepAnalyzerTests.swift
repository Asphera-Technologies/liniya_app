//
//  SleepAnalyzerTests.swift
//  LineaCoreTests
//
//  §6 «SleepAnalyzer»: the night of the brief must come out as 6:03 even
//  though the iPhone reports the same hours as «in bed» — double counting the
//  Watch and the phone is the most expensive mistake this analyzer can make,
//  so it is the first thing pinned down here.
//

import Testing
import Foundation
@testable import LineaCore

@Suite("SleepAnalyzer")
struct SleepAnalyzerTests {
    let analyzer = SleepAnalyzer()
    let time = WowFixture.morning

    /// A sleep segment of an arbitrary source, offset in whole days from the fixture's today.
    private func segment(
        _ stage: SleepStage,
        from: (Int, Int),
        to: (Int, Int),
        source: String = "com.example.tracker",
        startDayOffset: Int = 0,
        endDayOffset: Int = 0
    ) -> ContextSignal {
        ContextSignal(
            kind: .sleepSegment,
            value: .interval(nil),
            start: WowFixture.moment(from.0, from.1, dayOffset: startDayOffset),
            end: WowFixture.moment(to.0, to.1, dayOffset: endDayOffset),
            source: .healthKit,
            attributes: [SignalAttribute.stage: stage.rawValue, SignalAttribute.sourceBundle: source]
        )
    }

    @Test("Watch + iPhone for the same night are not summed: 6:03 from the staged source")
    func watchWinsOverPhone() throws {
        let signals = WowFixture.sleepSignalsWatch + WowFixture.sleepSignalsPhone
        let night = try #require(analyzer.night(for: WowFixture.today, signals: signals, time: time))

        #expect(night.asleepSeconds == 21_780)                   // 6:03, not 6:03 + 7:00
        #expect(night.quality == 1.0)                            // staged source
        #expect(night.sourceName == "com.apple.health.watch")
        #expect(time.timeOfDay(of: night.bedtime) == TimeOfDay(hour: 0, minute: 57))
        #expect(time.timeOfDay(of: night.wakeTime) == TimeOfDay(hour: 7, minute: 12))
        #expect(night.awakenings == 1)                           // the 3:20 → 3:32 gap
        #expect(night.day == WowFixture.today)
    }

    @Test("Stages are reported per stage and add up to the asleep total")
    func stages() throws {
        let night = try #require(analyzer.night(for: WowFixture.today, signals: WowFixture.sleepSignalsWatch, time: time))

        #expect(night.stages[.core] == 11_700)                   // 195 min
        #expect(night.stages[.deep] == 3_000)                    // 50 min
        #expect(night.stages[.rem] == 7_080)                     // 118 min
        #expect(night.stages[.inBed] == nil)
        let asleep = [SleepStage.core, .deep, .rem].compactMap { night.stages[$0] }.reduce(0, +)
        #expect(asleep == night.asleepSeconds)
        #expect(night.inBedSeconds == 24_000)                    // the Watch «in bed» segment 00:40–07:20
    }

    @Test("iPhone alone: asleep is estimated as 0.9 · inBed with quality 0.5")
    func phoneOnly() throws {
        let night = try #require(analyzer.night(for: WowFixture.today, signals: WowFixture.sleepSignalsPhone, time: time))

        #expect(night.inBedSeconds == 25_200)                    // 00:30–07:30
        #expect(night.asleepSeconds == 22_680)                   // 0.9 · 7 h
        #expect(night.quality == 0.5)
        #expect(night.stages.isEmpty)
        #expect(night.awakenings == 0)
    }

    @Test("A night that starts before midnight belongs to the wake-up day")
    func nightAcrossMidnight() throws {
        let signals = [segment(.core, from: (23, 40), to: (6, 0), startDayOffset: -1, endDayOffset: 0)]
        let night = try #require(analyzer.night(for: WowFixture.today, signals: signals, time: time))

        #expect(night.day == WowFixture.today)
        #expect(night.bedtime == WowFixture.moment(23, 40, dayOffset: -1))
        #expect(night.wakeTime == WowFixture.moment(6, 0))
        #expect(night.asleepSeconds == 22_800)                   // 23:40 → 06:00
        #expect(night.quality == 1.0)
        // Yesterday's window closed at 12:00 yesterday — this night is not in it.
        #expect(analyzer.night(for: WowFixture.moment(12, 0, dayOffset: -1), signals: signals, time: time) == nil)
    }

    @Test("A daytime nap falls outside every night window")
    func daytimeNapIgnored() {
        let nap = segment(.core, from: (14, 0), to: (15, 0))

        #expect(analyzer.nightDay(containing: WowFixture.moment(14, 30), time: time) == nil)
        #expect(analyzer.night(for: WowFixture.today, signals: [nap], time: time) == nil)
        #expect(analyzer.nights(signals: [nap], time: time).isEmpty)
        // …and it does not disturb the real night either.
        let night = analyzer.night(for: WowFixture.today, signals: WowFixture.sleepSignalsWatch + [nap], time: time)
        #expect(night?.asleepSeconds == 21_780)
    }

    @Test("nights(_:) returns one night per day, oldest first")
    func nightsAreSortedByDay() {
        let signals = WowFixture.sleepSignalsWatch
            + [segment(.core, from: (1, 0), to: (6, 0), startDayOffset: -2, endDayOffset: -2)]
            + [segment(.core, from: (23, 0), to: (5, 30), startDayOffset: -2, endDayOffset: -1)]
            + [segment(.core, from: (14, 0), to: (15, 0))]      // nap — ignored

        let nights = analyzer.nights(signals: signals, time: time)

        #expect(nights.map(\.day) == [
            WowFixture.moment(0, 0, dayOffset: -2),
            WowFixture.moment(0, 0, dayOffset: -1),
            WowFixture.today,
        ])
        let expected: [TimeInterval] = [18_000, 23_400, 21_780]
        #expect(nights.map(\.asleepSeconds) == expected)
    }

    @Test("No usable segments at all → no night")
    func emptyInput() {
        #expect(analyzer.night(for: WowFixture.today, signals: [], time: time) == nil)
        #expect(analyzer.nights(signals: [], time: time).isEmpty)
        // Non-sleep signals and zero-length segments are not sleep either.
        let junk = WowFixture.hrvSignals + [segment(.core, from: (2, 0), to: (2, 0))]
        #expect(analyzer.night(for: WowFixture.today, signals: junk, time: time) == nil)
    }

    @Test("Without stages the source is still used, with a lower quality")
    func unstagedSource() throws {
        let signals = [
            segment(.unspecified, from: (1, 0), to: (4, 0)),
            segment(.unspecified, from: (4, 20), to: (7, 0)),
        ]
        let night = try #require(analyzer.night(for: WowFixture.today, signals: signals, time: time))

        #expect(night.quality == 0.8)
        #expect(night.asleepSeconds == 20_400)                   // 3:00 + 2:40
        #expect(night.inBedSeconds == 21_600)                    // span 01:00–07:00, no «in bed» segments
        #expect(night.awakenings == 1)
    }
}
