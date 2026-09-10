//
//  StrainStateAnalyzer.swift
//  Linea
//
//  The `strain` component: did yesterday's training exceed what this user
//  usually does? Simplified on purpose (minutes, no TRIMP/ACWR — v1 has no
//  heart-rate zones). A day without a workout yesterday says nothing about
//  strain, so the component is absent rather than «fresh».
//

import Foundation

nonisolated struct StrainStateAnalyzer: StateAnalyzer {
    let kind: StateComponentKind = .strain

    /// Minimum «usual» denominator so a first-ever 40-minute run is not «high load».
    var minimumUsualMinutes = 60.0
    var highLoadRatio = 1.3

    init() {}

    func analyze(_ input: StateInput) -> StateComponent? {
        let yesterday = input.time.adding(days: -1, to: input.time.startOfDay(input.snapshot.day))
        guard let minutes = input.history.last(where: { input.time.isSameDay($0.day, yesterday) })?[.workoutMinutes],
              minutes > 0 else { return nil }

        let baseline = input.baselines?[.workoutMinutes]
        let usual = max((baseline?.median ?? 0) + (baseline?.spread ?? 0), minimumUsualMinutes)
        let yesterdayStrain = minutes / usual
        let score = StateMath.clamp(1 - 0.5 * max(0, yesterdayStrain - 1))

        var facts: [Fact] = []
        if yesterdayStrain >= highLoadRatio { facts.append(.highLoadYesterday) }

        var level: UsualLevel = .unknown
        let z = baseline?.z(minutes)
        if let baseline, baseline.isReliable, let z {
            level = z <= -0.7 ? .belowUsual : (z >= 0.7 ? .aboveUsual : .usual)
        }

        let confidence = 0.5 + 0.5 * (baseline?.confidence ?? 0)
        return StateComponent(kind: kind, score: score, confidence: confidence, z: z, level: level, facts: facts)
    }
}
