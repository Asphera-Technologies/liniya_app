//
//  RecoveryStateAnalyzer.swift
//  Linea
//
//  The `recovery` component from HRV (ln, night median) and resting heart
//  rate, both as z-scores against the PERSONAL baseline. Population norms
//  are deliberately not used: between-person spread of HRV is larger than
//  within-person, so «38 ms» means nothing until we know this user's 52.
//  Until then the component is neutral (0.5) with low confidence.
//

import Foundation

nonisolated struct RecoveryStateAnalyzer: StateAnalyzer {
    let kind: StateComponentKind = .recovery

    var seriesBuilder = DailySeriesBuilder()
    var hrvWeight = 0.6
    var rhrWeight = 0.4
    var coldStartConfidence = 0.15

    init() {}

    func analyze(_ input: StateInput) -> StateComponent? {
        let today = seriesBuilder.build(snapshot: input.snapshot, time: input.time).summary
        let hrvLog = today[.hrvLog]
        let rhr = today[.restingHeartRate]
        guard hrvLog != nil || rhr != nil else { return nil }

        var facts: [Fact] = []
        if hrvLog == nil { facts.append(.dataMissing(kind: .hrvSDNN)) }
        if rhr == nil { facts.append(.dataMissing(kind: .restingHeartRate)) }

        let hrvBaseline = hrvLog == nil ? nil : input.baselines?[.hrvLog]
        let rhrBaseline = rhr == nil ? nil : input.baselines?[.restingHeartRate]
        let cHRV = hrvBaseline?.confidence ?? 0
        let cRHR = rhrBaseline?.confidence ?? 0
        let weightSum = hrvWeight * cHRV + rhrWeight * cRHR

        let days = max(
            hrvLog == nil ? 0 : input.history.filter { $0[.hrvLog] != nil }.count,
            rhr == nil ? 0 : input.history.filter { $0[.restingHeartRate] != nil }.count
        )

        // Cold start: today has a value, but nothing to compare it with yet.
        guard weightSum > 0 else {
            facts.append(.coldStart(days: days, needed: Baseline.reliableSampleCount))
            facts.append(.recovery(level: .unknown))
            return StateComponent(kind: kind, score: 0.5, confidence: coldStartConfidence, z: nil, level: .unknown, facts: facts)
        }

        var scoreSum = 0.0
        var zSum = 0.0
        var reliable = true
        var zHRV: Double?
        var zRHR: Double?
        if let hrvLog, let hrvBaseline {
            let z = hrvBaseline.z(hrvLog)
            zHRV = z
            scoreSum += hrvWeight * cHRV * StateMath.clamp(0.5 + 0.2 * z)
            zSum += hrvWeight * cHRV * z
            reliable = reliable && hrvBaseline.isReliable
        }
        if let rhr, let rhrBaseline {
            let z = rhrBaseline.z(rhr)
            zRHR = z
            scoreSum += rhrWeight * cRHR * StateMath.clamp(0.5 - 0.2 * z)
            zSum -= rhrWeight * cRHR * z          // higher resting HR = worse recovery
            reliable = reliable && rhrBaseline.isReliable
        }
        let score = scoreSum / weightSum
        let z = zSum / weightSum

        var level: UsualLevel = .unknown
        if reliable {
            level = z <= -0.7 ? .belowUsual : (z >= 0.7 ? .aboveUsual : .usual)
            if let zHRV { facts.append(.hrvVsUsual(z: zHRV)) }
            if let zRHR { facts.append(.restingHeartRateVsUsual(z: zRHR)) }
        } else {
            facts.append(.coldStart(days: days, needed: Baseline.reliableSampleCount))
        }
        facts.append(.recovery(level: level))

        let confidence = max(coldStartConfidence, weightSum / (hrvWeight + rhrWeight))
        return StateComponent(kind: kind, score: score, confidence: confidence, z: z, level: level, facts: facts)
    }
}
