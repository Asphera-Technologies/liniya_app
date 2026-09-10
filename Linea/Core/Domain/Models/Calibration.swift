//
//  Calibration.swift
//  Linea
//
//  What the Feedback Engine is allowed to change (few, bounded knobs) and the
//  static engine constants it is NOT allowed to change (weights are logged,
//  not learned — three buttons a day cannot identify five weights).
//

import Foundation

/// Learned per-user adjustments. Every change is bounded and logged.
nonisolated struct Calibration: Codable, Hashable, Sendable {
    static let schemaVersion = 1

    /// Added to fused energy; EMA of (rating − predicted). [−0.15, +0.15]
    var energyBias: Double
    /// Energy below which the day is `.reduce`. [0.30, 0.55]
    var reduceThreshold: Double
    /// Energy above which the day may be `.push`. [0.60, 0.85]
    var pushThreshold: Double
    /// Multiplies available planning minutes. [0.5, 1.1]
    var capacityFactor: Double
    /// Multiplies task estimates (people underestimate). [0.8, 2.0]
    var estimateMultiplier: Double
    /// Minutes after a block's end before a «behind schedule» nudge. [10, 45]
    var nudgeGraceMinutes: Int
    /// Multiplies the nudge cooldown after dismissals. [1, 3]
    var nudgeCooldownMultiplier: Double
    /// Last local day whose evening rating was applied (idempotency).
    var lastRatingAppliedDay: Date?
    var ratingsCount: Int
    var changeLog: [CalibrationChange]

    init(
        energyBias: Double = 0,
        reduceThreshold: Double = 0.40,
        pushThreshold: Double = 0.70,
        capacityFactor: Double = 1.0,
        estimateMultiplier: Double = 1.0,
        nudgeGraceMinutes: Int = 15,
        nudgeCooldownMultiplier: Double = 1.0,
        lastRatingAppliedDay: Date? = nil,
        ratingsCount: Int = 0,
        changeLog: [CalibrationChange] = []
    ) {
        self.energyBias = energyBias
        self.reduceThreshold = reduceThreshold
        self.pushThreshold = pushThreshold
        self.capacityFactor = capacityFactor
        self.estimateMultiplier = estimateMultiplier
        self.nudgeGraceMinutes = nudgeGraceMinutes
        self.nudgeCooldownMultiplier = nudgeCooldownMultiplier
        self.lastRatingAppliedDay = lastRatingAppliedDay
        self.ratingsCount = ratingsCount
        self.changeLog = changeLog
    }

    static let `default` = Calibration()
}

nonisolated struct CalibrationChange: Codable, Hashable, Sendable {
    let at: Date
    let parameter: String
    let from: Double
    let to: Double
    let reason: String
}

/// Static engine constants. Change here = product decision, not learning.
nonisolated struct EngineConfig: Sendable {
    // Scoring (brief: urgency + importance + goalAlignment + energyFit + durationFit)
    var weightUrgency: Double = 0.30
    var weightImportance: Double = 0.25
    var weightGoalAlignment: Double = 0.15
    var weightEnergyFit: Double = 0.20
    var weightDurationFit: Double = 0.10

    // State fusion weights by component kind (normalised over available components)
    var componentWeights: [StateComponentKind: Double] = [.sleep: 0.45, .recovery: 0.35, .strain: 0.20, .fuel: 0.10]
    /// Below this fused confidence, energy is treated as unknown for planning.
    var minimumEnergyConfidence: Double = 0.35
    /// Hysteresis around load thresholds to avoid flapping day to day.
    var loadHysteresis: Double = 0.03

    // Baselines
    var baselineWindowDays: Int = 28

    // Planning
    var maxTopTasks: Int = 3
    var maxDeepTasksWhenReduced: Int = 1
    var blockBufferMinutes: Int = 10
    var minimumBlockMinutes: Int = 15
    /// Deep work is only placed in slots with circadian alertness ≥ this when the day is `.reduce`.
    var deepWorkAlertnessFloor: Double = 0.85
    /// No deep work after this hour when the day is `.reduce`.
    var deepWorkLatestHourWhenReduced: Int = 16
    /// Planned focus minutes ≤ this share of available minutes.
    var loadCapNormal: Double = 1.0
    var loadCapReduced: Double = 0.75

    // Nudges
    var nudgeCooldownMinutes: Int = 90
    var maxNudgesPerDay: Int = 3
    /// Ignore a behind-schedule nudge if less than this remains before the next commitment.
    var nudgeMinimumWindowMinutes: Int = 20

    init() {}

    static let `default` = EngineConfig()
}
