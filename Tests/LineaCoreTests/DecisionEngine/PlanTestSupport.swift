//
//  PlanTestSupport.swift
//  LineaCoreTests
//
//  Shared scaffolding for the Decision Engine suites: a renderer stub that
//  echoes the structure it was given (so tests assert FACTS, never Russian
//  wording), the wow-scenario `UserState` with the numbers of the brief, and
//  small helpers to describe a plan as a timeline.
//

import Foundation
import Testing
@testable import LineaCore

/// Renders nothing human — just enough structure to prove the engines called a
/// renderer with the right moment and facts.
nonisolated struct StubRenderer: TextRenderer {
    let id: String

    init(id: String = "stub") { self.id = id }

    func render(_ request: ExplanationRequest) -> Explanation {
        Explanation(
            headline: "headline:\(request.moment.rawValue)",
            body: "body:\(request.facts.count):\(request.taskTitles.joined(separator: "|"))",
            reasons: request.facts.map { "\($0)" },
            explainerID: id
        )
    }
}

nonisolated enum PlanFixture {
    /// The state the State Engine produces for the wow-scenario: 6:03 of sleep
    /// against a usual 7:13, recovery below usual → energy 0.38, `.reduce`.
    static func reducedState(at time: TimeContext = WowFixture.morning) -> UserState {
        state(energy: 0.38, confidence: 0.9, advice: .reduce, at: time)
    }

    /// «Apple Health не подключён»: nothing is known, energy is neutral.
    static func unknownState(at time: TimeContext = WowFixture.morning) -> UserState {
        UserState(
            day: WowFixture.today, computedAt: time.now, components: [],
            energy: 0.5, confidence: 0, loadAdvice: .unknown,
            facts: [.energy(value: 0.5, confidence: 0), .loadAdvice(.unknown), .dataMissing(kind: .sleepSegment)]
        )
    }

    static func state(energy: Double, confidence: Double, advice: LoadAdvice, at time: TimeContext = WowFixture.morning) -> UserState {
        let sleep = StateComponent(
            kind: .sleep, score: 0.42, confidence: 0.9, z: -1.4, level: .belowUsual,
            facts: [.sleepDuration(seconds: 21_780), .sleepBaseline(seconds: 25_980),
                    .sleepVsUsual(deltaSeconds: -4_200, level: .belowUsual)]
        )
        let recovery = StateComponent(
            kind: .recovery, score: 0.36, confidence: 0.9, z: -1.1, level: .belowUsual,
            facts: [.recovery(level: .belowUsual), .hrvVsUsual(z: -1.2), .restingHeartRateVsUsual(z: 0.8)]
        )
        return UserState(
            day: WowFixture.today, computedAt: time.now,
            components: [sleep, recovery],
            energy: energy, confidence: confidence, loadAdvice: advice,
            facts: sleep.facts + recovery.facts + [.energy(value: energy, confidence: confidence), .loadAdvice(advice)]
        )
    }

    /// A snapshot with custom tasks but the wow-scenario day, goals and commitments.
    static func snapshot(
        tasks: [LineaTask],
        commitments: [Commitment]? = nil,
        goals: [LineaGoal]? = nil,
        at time: TimeContext = WowFixture.morning
    ) -> ContextSnapshot {
        ContextSnapshot(
            id: WowFixture.snapshotID, day: WowFixture.today, capturedAt: time.now,
            timeZoneIdentifier: WowFixture.timeZoneID, signals: [],
            providerStatuses: [.healthKit: .ready],
            tasks: tasks, goals: goals ?? WowFixture.goals,
            commitments: commitments ?? WowFixture.defaultCommitments,
            profile: WowFixture.profile, nutrition: WowFixture.nutrition, meals: []
        )
    }

    static func engine(rules: [any PlanRule] = [DayBriefRule()], config: EngineConfig = .default) -> DecisionEngine {
        DecisionEngine(rules: rules, renderer: StubRenderer(), config: config)
    }

    static func nudgeEngine(config: EngineConfig = .default) -> NudgeEngine {
        NudgeEngine(renderer: StubRenderer(), config: config)
    }

    // MARK: Describing a plan

    static func hhmm(_ date: Date, time: TimeContext = WowFixture.morning) -> String {
        let tod = time.timeOfDay(of: date)
        return String(format: "%02d:%02d", tod.hour, tod.minute)
    }

    /// «09:00–10:30 focus Презентация КП» per line — used to pin the timeline.
    static func timeline(_ plan: DayPlan) -> [String] {
        plan.blocks.map { "\(hhmm($0.start))–\(hhmm($0.end)) \($0.kind.rawValue) \($0.title)" }
    }

    static func identity(_ plan: DayPlan) -> [String] {
        plan.blocks.map { "\($0.id)|\($0.start.timeIntervalSince1970)|\($0.end.timeIntervalSince1970)" }
    }

    static func overlaps(_ blocks: [PlanBlock]) -> Bool {
        let sorted = blocks.sorted { $0.start < $1.start }
        for index in sorted.indices.dropFirst() where sorted[index].start < sorted[index - 1].end {
            return true
        }
        return false
    }

    // MARK: Fact accessors

    static func nextCommitmentFact(_ facts: [Fact]) -> (title: String, at: Date, minutesLeft: Int)? {
        for fact in facts {
            if case .nextCommitment(let title, let at, let minutesLeft) = fact { return (title, at, minutesLeft) }
        }
        return nil
    }

    static func hardWorkDeadline(_ facts: [Fact]) -> Date? {
        for fact in facts {
            if case .hardWorkDeadline(let date) = fact { return date }
        }
        return nil
    }

    static func topTaskCount(_ facts: [Fact]) -> Int? {
        for fact in facts {
            if case .topTaskCount(let count) = fact { return count }
        }
        return nil
    }

    static func mealWindow(_ facts: [Fact]) -> (kind: MealKind, start: Date, end: Date)? {
        for fact in facts {
            if case .mealWindow(let kind, let start, let end) = fact { return (kind, start, end) }
        }
        return nil
    }

    static func workoutPlanned(_ facts: [Fact]) -> Date? {
        for fact in facts {
            if case .workoutPlanned(let at) = fact { return at }
        }
        return nil
    }

    static func plannedTaskIDs(_ facts: [Fact]) -> [UUID] {
        facts.compactMap { fact in
            if case .taskPlanned(let taskID, _, _, _) = fact { return taskID }
            return nil
        }
    }

    static func deferredFactIDs(_ facts: [Fact]) -> [UUID] {
        facts.compactMap { fact in
            if case .taskDeferred(let taskID, _, _) = fact { return taskID }
            return nil
        }
    }
}
