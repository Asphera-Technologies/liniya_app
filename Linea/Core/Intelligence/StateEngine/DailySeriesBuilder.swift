//
//  DailySeriesBuilder.swift
//  Linea
//
//  Today's row of the daily series: the same `DailyHealthSummary` shape the
//  history is stored in, computed from raw signals. Baselines compare this
//  row with the past, so aggregation rules here and in the HealthKit history
//  reader must agree (sleep via SleepAnalyzer, HRV as ln of the night median).
//
//  Physiologically impossible inputs are dropped here, once, so no engine
//  downstream has to re-check them.
//

import Foundation

/// Today's aggregates plus the night they came from.
nonisolated struct DailySeries: Sendable {
    let day: Date
    let sleepNight: SleepNight?
    let summary: DailyHealthSummary
}

nonisolated struct DailySeriesBuilder: Sendable {
    var sleepAnalyzer = SleepAnalyzer()
    /// HRV samples in [00:00, this hour) are «night» samples; they win over the whole day.
    var hrvNightEnd = TimeOfDay(hour: 12)

    init() {}

    // MARK: Validation

    static let maxSleepSeconds: TimeInterval = 16 * 3600
    static let hrvRange: ClosedRange<Double> = 0...300
    static let restingHeartRateRange: ClosedRange<Double> = 30...120

    /// Whether a daily value is plausible for its kind (unknown kinds pass).
    static func isValid(_ kind: SignalKind, _ value: Double) -> Bool {
        guard value.isFinite else { return false }
        switch kind {
        case .sleepAsleep, .sleepInBed: return value >= 0 && value <= maxSleepSeconds
        case .hrvLog: return value.isFinite && exp(value) > 0 && exp(value) <= hrvRange.upperBound
        case .restingHeartRate: return restingHeartRateRange.contains(value)
        case .steps, .activeEnergy, .workoutMinutes: return value >= 0
        default: return true
        }
    }

    static func isValidHRVSample(_ ms: Double) -> Bool { ms.isFinite && ms > 0 && ms <= hrvRange.upperBound }

    /// A copy of `summary` with implausible values removed.
    static func validated(_ summary: DailyHealthSummary) -> DailyHealthSummary {
        var clean = summary
        clean.values = summary.values.filter { isValid($0.key, $0.value) }
        // A night that is impossible drops every sleep-derived value together.
        if let asleep = summary[.sleepAsleep], !isValid(.sleepAsleep, asleep) {
            clean[.sleepInBed] = nil
            clean[.sleepBedtime] = nil
        }
        return clean
    }

    // MARK: Building

    func build(snapshot: ContextSnapshot, time: TimeContext) -> DailySeries {
        build(day: snapshot.day, signals: snapshot.signals, time: time)
    }

    func build(day: Date, signals: [ContextSignal], time: TimeContext) -> DailySeries {
        let dayStart = time.startOfDay(day)
        let dayInterval = time.dayInterval(containing: dayStart)
        var values: [SignalKind: Double] = [:]

        // Sleep
        var night = sleepAnalyzer.night(for: dayStart, signals: signals, time: time)
        if let n = night, !Self.isValid(.sleepAsleep, n.asleepSeconds) { night = nil }
        if let n = night {
            values[.sleepAsleep] = n.asleepSeconds
            values[.sleepInBed] = n.inBedSeconds
            values[.sleepBedtime] = n.bedtime.timeIntervalSince(dayStart) / 60
        }

        let today = signals.filter { dayInterval.contains($0.start) && $0.start < dayInterval.end }

        // HRV: night samples first, else the whole day; ln because HRV is log-normal.
        let hrv = today.filter { $0.kind == .hrvSDNN }.compactMap { s -> (Date, Double)? in
            guard let v = s.value.number, Self.isValidHRVSample(v) else { return nil }
            return (s.start, v)
        }
        let nightEnd = time.date(on: dayStart, at: hrvNightEnd)
        let nightHRV = hrv.filter { $0.0 < nightEnd }
        if let median = StateMath.median((nightHRV.isEmpty ? hrv : nightHRV).map(\.1)) {
            values[.hrvLog] = log(median)
        }

        // Resting heart rate: the latest sample of the day.
        let rhr = today.filter { $0.kind == .restingHeartRate }
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
            .compactMap { s -> Double? in
                guard let v = s.value.number, Self.isValid(.restingHeartRate, v) else { return nil }
                return v
            }
        if let last = rhr.last { values[.restingHeartRate] = last }

        // Cumulative counters
        let steps = today.filter { $0.kind == .steps }.compactMap { $0.value.number }
        if !steps.isEmpty { values[.steps] = steps.reduce(0, +) }
        let energy = today.filter { $0.kind == .activeEnergy }.compactMap { $0.value.number }
        if !energy.isEmpty { values[.activeEnergy] = energy.reduce(0, +) }
        let workouts = today.filter { $0.kind == .workout }
        if !workouts.isEmpty { values[.workoutMinutes] = workouts.reduce(0) { $0 + $1.duration } / 60 }

        return DailySeries(day: dayStart, sleepNight: night, summary: Self.validated(DailyHealthSummary(day: dayStart, values: values)))
    }
}
