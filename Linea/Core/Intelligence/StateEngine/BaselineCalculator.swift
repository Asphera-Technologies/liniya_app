//
//  BaselineCalculator.swift
//  Linea
//
//  Personal «usual» per metric: median and MAD over the baseline window
//  (history only — today is what gets compared). Robust statistics because
//  one night of 3 hours must not move «usual»; floors on the spread because a
//  very regular sleeper would otherwise get a z of −3 from a 20-minute
//  shortfall.
//

import Foundation

nonisolated struct BaselineCalculator: Sendable {
    /// Minimum spread per kind (canonical units): sleep 30 min, hrvLog 0.10,
    /// RHR 2 bpm, steps 1500, energy 100 kcal, workouts 15 min, bedtime 30 min.
    static let defaultFloors: [SignalKind: Double] = [
        .sleepAsleep: 1800,
        .sleepInBed: 1800,
        .sleepBedtime: 30,
        .hrvLog: 0.10,
        .restingHeartRate: 2,
        .steps: 1500,
        .activeEnergy: 100,
        .workoutMinutes: 15,
    ]

    var floors: [SignalKind: Double]
    var minimumSampleCount: Int

    init(floors: [SignalKind: Double] = BaselineCalculator.defaultFloors, minimumSampleCount: Int = Baseline.minimumSampleCount) {
        self.floors = floors
        self.minimumSampleCount = minimumSampleCount
    }

    /// Baselines for every kind seen in `history` within the last
    /// `config.baselineWindowDays` local days before today (today excluded).
    func compute(history: [DailyHealthSummary], config: EngineConfig, time: TimeContext) -> BaselineSet {
        let windowDays = config.baselineWindowDays
        let today = time.today
        let windowStart = time.adding(days: -windowDays, to: today)

        // One row per local day (later rows win), implausible values dropped.
        var rows: [Date: DailyHealthSummary] = [:]
        for summary in history {
            let day = time.startOfDay(summary.day)
            guard day >= windowStart, day < today else { continue }
            rows[day] = DailySeriesBuilder.validated(summary)
        }

        var byKind: [SignalKind: [Double]] = [:]
        for day in rows.keys.sorted() {
            for (kind, value) in rows[day]?.values ?? [:] {
                byKind[kind, default: []].append(value)
            }
        }

        var baselines: [SignalKind: Baseline] = [:]
        for (kind, values) in byKind {
            if let baseline = baseline(kind: kind, values: values, windowDays: windowDays) {
                baselines[kind] = baseline
            }
        }
        return BaselineSet(baselines: baselines, computedAt: time.now, windowDays: windowDays)
    }

    /// Baseline for one kind from its daily values; nil below the minimum sample count.
    func baseline(kind: SignalKind, values: [Double], windowDays: Int) -> Baseline? {
        guard values.count >= minimumSampleCount, let median = StateMath.median(values) else { return nil }
        let mad = StateMath.mad(values, center: median) ?? 0
        let spread = max(1.4826 * mad, floors[kind] ?? 0)
        return Baseline(kind: kind, median: median, spread: spread, sampleCount: values.count, windowDays: windowDays)
    }
}
