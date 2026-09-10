//
//  StateEngineTests.swift
//  LineaCoreTests
//
//  The wow-scenario of the brief as an executable contract: 6:03 of sleep
//  against a usual 7:13, HRV 38 against 52, resting HR 58 against 54 must come
//  out as «энергия ниже обычного, разгружаем день» — with the exact numbers
//  documentation quotes. The rest of the suite guards the ways the engine may
//  NOT fail: degraded data must lower confidence instead of inventing a verdict,
//  a four-hour night must stay `reduce` however good the recovery looks, and
//  the same input must always produce the same output.
//

import Testing
import Foundation
@testable import LineaCore

@Suite("StateEngine")
struct StateEngineTests {
    let engine = StateEngine()

    // MARK: Helpers

    private func input(
        snapshot: ContextSnapshot? = nil,
        history: [DailyHealthSummary]? = nil,
        calibration: Calibration = .default,
        time: TimeContext = WowFixture.morning,
        previousLoadAdvice: LoadAdvice? = nil
    ) -> StateInput {
        StateInput(
            snapshot: snapshot ?? WowFixture.snapshot(),
            baselines: nil,
            history: history ?? WowFixture.history,
            calibration: calibration,
            time: time,
            previousLoadAdvice: previousLoadAdvice
        )
    }

    private func hasSleepVsUsual(_ facts: [Fact]) -> Bool {
        facts.contains {
            if case .sleepVsUsual = $0 { return true }
            return false
        }
    }

    private func hasColdStart(_ facts: [Fact]) -> Bool {
        facts.contains {
            if case .coldStart = $0 { return true }
            return false
        }
    }

    // MARK: The wow-scenario

    @Test("Wow-scenario: 6:03 against a usual 7:13 is a reduce day")
    func wowScenario() throws {
        let state = engine.evaluate(input())

        let sleep = try #require(state.component(.sleep))
        let sleepZ = try #require(sleep.z)
        #expect(sleep.level == .belowUsual)
        #expect(abs(sleepZ + 7.0 / 3) < 1e-9)                         // (21 780 − 25 980) / 1800
        #expect(abs(sleep.score - 0.673559695) < 1e-6)
        #expect(sleep.confidence == 1.0)
        #expect(sleep.facts.contains(.sleepDuration(seconds: 21_780)))
        #expect(sleep.facts.contains(.sleepBaseline(seconds: 25_980)))
        #expect(sleep.facts.contains(.sleepVsUsual(deltaSeconds: -4_200, level: .belowUsual)))
        #expect(sleep.facts.contains(.sleepShortAbsolute(seconds: 21_780)) == false)   // 6:03 is not < 5 h

        let recovery = try #require(state.component(.recovery))
        let recoveryZ = try #require(recovery.z)
        #expect(recovery.level == .belowUsual)
        #expect(abs(recovery.score - 0.04) < 1e-9)                    // HRV z −3 → 0, RHR z +2 → 0.1
        #expect(abs(recoveryZ + 2.6) < 1e-9)
        #expect(recovery.confidence == 1.0)
        #expect(recovery.facts.contains(.recovery(level: .belowUsual)))

        // No workout yesterday → the strain component has nothing to say.
        #expect(state.component(.strain) == nil)

        #expect(abs(state.energy - 0.396377329) < 1e-6)
        #expect(state.energy < 0.45)
        #expect(state.confidence == 1.0)
        #expect(state.loadAdvice == .reduce)
        #expect(state.facts.contains(.loadAdvice(.reduce)))
        #expect(state.facts.contains(.energy(value: state.energy, confidence: state.confidence)))

        #expect(state.sleepNight?.asleepSeconds == 21_780)
        #expect(state.baselineProgress == nil)                        // the baseline is complete
        #expect(hasColdStart(state.facts) == false)
        #expect(state.day == WowFixture.today)
        #expect(state.computedAt == WowFixture.morning.now)
    }

    // MARK: Degradation

    @Test("No history: absolute numbers, no «обычно», lower confidence")
    func coldStart() throws {
        let full = engine.evaluate(input())
        let state = engine.evaluate(input(history: []))

        #expect(hasColdStart(state.facts))
        #expect(hasSleepVsUsual(state.facts) == false)
        #expect(state.facts.contains(.sleepDuration(seconds: 21_780)))
        #expect(state.confidence < full.confidence)
        #expect(abs(state.confidence - 0.290625) < 1e-9)              // sleep 0.4 · 0.45 + recovery 0.15 · 0.35, over 0.8

        let sleep = try #require(state.component(.sleep))
        #expect(sleep.level == .unknown)                              // «обычно» is not available yet
        #expect(sleep.z == nil)
        let recovery = try #require(state.component(.recovery))
        #expect(recovery.score == 0.5)                                // neutral, not «bad»
        #expect(recovery.confidence == 0.15)

        let progress = try #require(state.baselineProgress)
        #expect(progress.days == 0)
        #expect(progress.needed == 7)
        #expect(progress.isComplete == false)
    }

    @Test("No health signals at all: neutral energy, unknown advice, the gap is a fact")
    func noHealthData() {
        let state = engine.evaluate(input(snapshot: WowFixture.snapshot(signals: [])))

        #expect(state.components.isEmpty)
        #expect(state.energy == 0.5)
        #expect(state.confidence == 0)
        #expect(state.loadAdvice == .unknown)
        #expect(state.sleepNight == nil)
        #expect(state.facts.contains(.dataMissing(kind: .sleepSegment)))
        #expect(state.facts.contains(.dataMissing(kind: .hrvSDNN)))
        #expect(state.facts.contains(.dataMissing(kind: .restingHeartRate)))
        #expect(state.facts.contains(.loadAdvice(.unknown)))
    }

    @Test("An unhealthy provider is reported as a fact, not silently ignored")
    func providerUnavailable() {
        let denied = ContextSnapshot(
            id: WowFixture.snapshotID,
            day: WowFixture.today,
            capturedAt: WowFixture.morning.now,
            timeZoneIdentifier: WowFixture.timeZoneID,
            signals: [],
            providerStatuses: [.healthKit: .unauthorized, .nutrition: .ready],
            tasks: WowFixture.tasks,
            goals: WowFixture.goals,
            commitments: WowFixture.defaultCommitments,
            profile: WowFixture.profile,
            nutrition: WowFixture.nutrition
        )
        let state = engine.evaluate(input(snapshot: denied))

        #expect(state.facts.contains(.providerUnavailable(provider: .healthKit, status: .unauthorized)))
        #expect(state.facts.contains(.providerUnavailable(provider: .nutrition, status: .ready)) == false)
        #expect(state.loadAdvice == .unknown)
    }

    // MARK: Rules that must never be outvoted

    @Test("Four hours of sleep is a reduce day however good HRV and resting HR look")
    func shortNightAlwaysReduces() throws {
        let signals: [ContextSignal] = [
            ContextSignal(kind: .sleepSegment, value: .interval(nil), start: WowFixture.moment(2), end: WowFixture.moment(6),
                          source: .healthKit,
                          attributes: [SignalAttribute.stage: SleepStage.core.rawValue, SignalAttribute.sourceBundle: "com.apple.health.watch"]),
            ContextSignal(kind: .hrvSDNN, value: .number(70), start: WowFixture.moment(3), source: .healthKit, unit: "ms"),
            ContextSignal(kind: .restingHeartRate, value: .number(50), start: WowFixture.moment(6, 30), source: .healthKit, unit: "bpm"),
        ]
        let state = engine.evaluate(input(snapshot: WowFixture.snapshot(signals: signals)))

        let recovery = try #require(state.component(.recovery))
        #expect(recovery.level == .aboveUsual)                        // recovery really is excellent
        #expect(recovery.score > 0.9)
        #expect(state.energy > 0.40)                                  // …and energy is above the reduce cut
        #expect(state.loadAdvice == .reduce)                          // …yet the night decides
        #expect(state.facts.contains(.sleepShortAbsolute(seconds: 4 * 3600)))
    }

    @Test("Hysteresis: yesterday's advice holds the verdict near the threshold")
    func hysteresis() {
        // Energy 0.3964 sits 0.016 above this user's reduce cut — inside the 0.03 band.
        let calibration = Calibration(reduceThreshold: 0.38)

        let fresh = engine.evaluate(input(calibration: calibration))
        let afterReduce = engine.evaluate(input(calibration: calibration, previousLoadAdvice: .reduce))
        let afterNormal = engine.evaluate(input(calibration: calibration, previousLoadAdvice: .normal))

        #expect(fresh.energy > calibration.reduceThreshold)
        #expect(fresh.loadAdvice == .normal)
        #expect(afterReduce.loadAdvice == .reduce)                    // cut raised to 0.41 — stay reduced
        #expect(afterNormal.loadAdvice == .normal)                    // cut lowered to 0.35 — stay normal
        #expect(afterReduce.energy == afterNormal.energy)             // only the verdict differs
    }

    @Test("Deterministic: the same input always yields the same state")
    func determinism() {
        let first = engine.evaluate(input())
        let second = engine.evaluate(input())

        #expect(first.energy == second.energy)
        #expect(first.confidence == second.confidence)
        #expect(first.loadAdvice == second.loadAdvice)
        #expect(first.facts == second.facts)
        #expect(first.components.map(\.kind) == second.components.map(\.kind))
        #expect(first.components.map(\.score) == second.components.map(\.score))
        #expect(first.sleepNight == second.sleepNight)
    }

    @Test("The calendar is injected: the same signals read differently in UTC")
    func timeZoneIsInjected() {
        let moscow = engine.evaluate(input())
        let utc = engine.evaluate(input(time: TimeContext(now: WowFixture.moment(8), timeZoneIdentifier: "UTC")))

        // In UTC the local day starts three hours earlier, so the night of the
        // brief belongs to the NEXT local day and today's row has no sleep.
        #expect(moscow.sleepNight != nil)
        #expect(utc.sleepNight == nil)
        #expect(utc.facts.contains(.dataMissing(kind: .sleepSegment)))
        #expect(utc.component(.sleep) == nil)
        #expect(utc.energy != moscow.energy)
        #expect(utc.day != moscow.day)
    }
}
