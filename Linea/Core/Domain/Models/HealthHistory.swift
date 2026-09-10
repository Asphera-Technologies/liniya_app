//
//  HealthHistory.swift
//  Linea
//
//  Daily aggregates and personal baselines. A baseline is what "usual" means
//  for THIS user; without it the app must not say «меньше обычного».
//

import Foundation

/// One local day of health values, keyed by signal kind (open map — a new
/// metric never changes this type). Values are in the kind's canonical unit:
/// sleep seconds, HRV ms, RHR bpm, steps count, energy kcal, workout minutes.
nonisolated struct DailyHealthSummary: Codable, Hashable, Sendable {
    let day: Date
    var values: [SignalKind: Double]

    init(day: Date, values: [SignalKind: Double] = [:]) {
        self.day = day
        self.values = values
    }

    subscript(kind: SignalKind) -> Double? {
        get { values[kind] }
        set { values[kind] = newValue }
    }
}

/// Derived daily kinds (aggregates, not raw signals).
nonisolated extension SignalKind {
    /// Seconds asleep for the night ending on that day.
    static let sleepAsleep: SignalKind = "health.sleep.asleep"
    /// Seconds in bed for the night ending on that day.
    static let sleepInBed: SignalKind = "health.sleep.inBed"
    /// Bedtime as minutes since local midnight (may be negative for before-midnight, e.g. 23:30 → -30).
    static let sleepBedtime: SignalKind = "health.sleep.bedtime"
    /// Natural log of nightly median HRV (ms) — HRV is log-normal.
    static let hrvLog: SignalKind = "health.hrv.log"
    /// Total workout minutes that day.
    static let workoutMinutes: SignalKind = "health.workout.minutes"
}

/// Robust personal baseline for one kind: median + MAD-based spread.
nonisolated struct Baseline: Codable, Hashable, Sendable {
    let kind: SignalKind
    let median: Double
    /// Robust sigma: max(1.4826·MAD, floor).
    let spread: Double
    let sampleCount: Int
    let windowDays: Int

    /// Enough days to compare "today vs usual" out loud.
    var isReliable: Bool { sampleCount >= Baseline.reliableSampleCount }
    /// 0…1 confidence ramp: 3 samples → 0, 11+ → 1.
    var confidence: Double { min(max(Double(sampleCount - 3) / 8, 0), 1) }

    /// z-score of a value against this baseline, clamped to ±3.
    func z(_ value: Double) -> Double {
        guard spread > 0 else { return 0 }
        return min(max((value - median) / spread, -3), 3)
    }

    static let reliableSampleCount = 7
    static let minimumSampleCount = 3
}

nonisolated struct BaselineSet: Codable, Sendable {
    var baselines: [SignalKind: Baseline]
    let computedAt: Date
    let windowDays: Int

    init(baselines: [SignalKind: Baseline] = [:], computedAt: Date, windowDays: Int) {
        self.baselines = baselines
        self.computedAt = computedAt
        self.windowDays = windowDays
    }

    subscript(kind: SignalKind) -> Baseline? { baselines[kind] }
}

/// One night of sleep, deduplicated across sources.
nonisolated struct SleepNight: Codable, Hashable, Sendable {
    /// The local day the night belongs to (the wake-up day).
    let day: Date
    let bedtime: Date
    let wakeTime: Date
    let asleepSeconds: TimeInterval
    let inBedSeconds: TimeInterval
    /// Seconds per stage when the source reports stages.
    let stages: [SleepStage: TimeInterval]
    /// 1 = staged data from one source; 0.8 = asleep without stages; 0.5 = inBed only (estimated).
    let quality: Double
    let sourceName: String?
    /// Gaps > 5 min between asleep segments.
    let awakenings: Int

    var efficiency: Double? {
        guard inBedSeconds > 0, inBedSeconds - asleepSeconds > 300 else { return nil }
        return min(asleepSeconds / inBedSeconds, 1)
    }
}
