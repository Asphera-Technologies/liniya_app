//
//  EnergyFusion.swift
//  Linea
//
//  Folds independent components into one daily energy and a load advice.
//  Confidence is part of the arithmetic: a low-confidence component pulls
//  the result towards neutral 0.5 instead of towards its own value, so a
//  cold-start day never looks like a bad day. Load thresholds are the user's
//  calibrated ones, with hysteresis against yesterday's advice so the verdict
//  does not flap around a threshold.
//

import Foundation

nonisolated struct EnergyFusion: Sendable {
    nonisolated struct Result: Sendable, Hashable {
        /// Weighted mean of component scores by weight × confidence (before shrinking to 0.5).
        let rawEnergy: Double
        /// Final energy 0…1 after shrinking by confidence and adding `energyBias`.
        let energy: Double
        /// Fused confidence `C = Σ w·c / Σ w`.
        let confidence: Double
    }

    /// Sleep below this is a `.reduce` day whatever the rest says.
    var absoluteShortSleepSeconds: TimeInterval = 5 * 3600
    /// Recovery score needed to allow `.push`.
    var pushRecoveryFloor = 0.6

    init() {}

    func fuse(components: [StateComponent], config: EngineConfig, calibration: Calibration) -> Result {
        let weighted = components.compactMap { component -> (w: Double, c: Double, s: Double)? in
            guard let w = config.componentWeights[component.kind], w > 0 else { return nil }
            return (w, component.confidence, component.score)
        }
        let weightSum = weighted.reduce(0) { $0 + $1.w }
        guard weightSum > 0 else { return Result(rawEnergy: 0.5, energy: StateMath.clamp(0.5 + calibration.energyBias), confidence: 0) }

        let confidence = weighted.reduce(0) { $0 + $1.w * $1.c } / weightSum
        let trustSum = weighted.reduce(0) { $0 + $1.w * $1.c }
        let raw = trustSum > 0 ? weighted.reduce(0) { $0 + $1.w * $1.c * $1.s } / trustSum : 0.5
        let energy = StateMath.clamp(confidence * raw + (1 - confidence) * 0.5 + calibration.energyBias)
        return Result(rawEnergy: raw, energy: energy, confidence: confidence)
    }

    /// Load advice from fused energy. `previous` is yesterday's advice (hysteresis),
    /// `recoveryScore` gates `.push`, `asleepSeconds` applies the absolute short-sleep rule.
    func loadAdvice(
        energy: Double,
        confidence: Double,
        recoveryScore: Double?,
        asleepSeconds: TimeInterval?,
        previous: LoadAdvice?,
        config: EngineConfig,
        calibration: Calibration
    ) -> LoadAdvice {
        var advice: LoadAdvice
        if confidence < config.minimumEnergyConfidence {
            advice = .unknown
        } else {
            let h = config.loadHysteresis
            var reduceCut = calibration.reduceThreshold
            var pushCut = calibration.pushThreshold
            switch previous {
            case .reduce:
                reduceCut += h            // stay «reduce» a little longer
            case .normal:
                reduceCut -= h            // leave «normal» only decisively
                pushCut += h
            case .push:
                pushCut -= h
            case .unknown, nil:
                break
            }
            if energy < reduceCut {
                advice = .reduce
            } else if energy > pushCut, let recoveryScore, recoveryScore >= pushRecoveryFloor {
                advice = .push
            } else {
                advice = .normal
            }
        }
        if let asleepSeconds, asleepSeconds < absoluteShortSleepSeconds {
            advice = .reduce
        }
        return advice
    }
}
