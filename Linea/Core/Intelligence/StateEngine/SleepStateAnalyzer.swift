//
//  SleepStateAnalyzer.swift
//  Linea
//
//  The `sleep` component: how last night compares to what this user needs.
//  «Usual» is the personal median once it is reliable (≥ 7 nights); before
//  that the profile's sleep need is the reference and confidence is capped,
//  so the narrator can only speak in absolute numbers.
//

import Foundation

nonisolated struct SleepStateAnalyzer: StateAnalyzer {
    let kind: StateComponentKind = .sleep

    var seriesBuilder = DailySeriesBuilder()
    /// Below this the night is short in absolute terms, whatever the baseline says.
    var shortSleepSeconds: TimeInterval = 5 * 3600
    /// Sleep debt is summed over this many nights (including last night).
    var debtNights = 7
    var debtMinimumNights = 4
    var debtCapSeconds: TimeInterval = 10 * 3600
    var debtFullSeconds: TimeInterval = 6 * 3600

    init() {}

    func analyze(_ input: StateInput) -> StateComponent? {
        let series = seriesBuilder.build(snapshot: input.snapshot, time: input.time)
        guard let night = series.sleepNight else { return nil }
        let asleep = night.asleepSeconds

        let baseline = input.baselines?[.sleepAsleep]
        let reliable = baseline?.isReliable == true
        let ref = reliable ? baseline!.median : input.snapshot.profile.sleepNeedSeconds

        // Scores (weights 0.60 / 0.15 / 0.25, normalised over what is available)
        var weighted: [(weight: Double, score: Double)] = []
        weighted.append((0.60, StateMath.lin(asleep, 0.6 * ref, ref)))
        if let efficiency = night.efficiency {
            weighted.append((0.15, StateMath.lin(efficiency, 0.75, 0.92)))
        }
        let pastNights = input.history
            .sorted { $0.day < $1.day }
            .suffix(debtNights - 1)
            .compactMap { $0[.sleepAsleep] }
        if pastNights.count + 1 >= debtMinimumNights {
            let debt = min(([asleep] + pastNights).reduce(0) { $0 + max(0, ref - $1) }, debtCapSeconds)
            weighted.append((0.25, 1 - StateMath.lin(debt, 0, debtFullSeconds)))
        }
        let totalWeight = weighted.reduce(0) { $0 + $1.weight }
        let score = weighted.reduce(0) { $0 + $1.weight * $1.score } / totalWeight * (0.8 + 0.2 * night.quality)

        // Level and facts — «обычно» only with a reliable baseline
        let z = baseline?.z(asleep)
        var level: UsualLevel = .unknown
        var facts: [Fact] = [.sleepDuration(seconds: asleep)]
        if reliable, let baseline, let z {
            if z <= -0.7 || asleep <= 0.85 * ref {
                level = .belowUsual
            } else if z >= 0.7 {
                level = .aboveUsual
            } else {
                level = .usual
            }
            facts.append(.sleepBaseline(seconds: baseline.median))
            facts.append(.sleepVsUsual(deltaSeconds: asleep - baseline.median, level: level))
        } else {
            let days = baseline?.sampleCount ?? input.history.filter { $0[.sleepAsleep] != nil }.count
            facts.append(.coldStart(days: days, needed: Baseline.reliableSampleCount))
        }
        if asleep < shortSleepSeconds { facts.append(.sleepShortAbsolute(seconds: asleep)) }
        if let efficiency = night.efficiency { facts.append(.sleepEfficiency(ratio: efficiency)) }

        let confidence = reliable
            ? night.quality * (0.7 + 0.3 * baseline!.confidence)
            : night.quality * 0.4

        return StateComponent(kind: kind, score: score, confidence: confidence, z: z, level: level, facts: facts)
    }
}
