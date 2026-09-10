//
//  HealthKitHistoryReader.swift
//  Linea
//
//  Reads what the intelligence core needs from Apple Health: today's raw
//  signals and the daily aggregates of the past weeks that personal baselines
//  are built from. Read-only, like the rest of the HealthKit boundary.
//
//  Two deliberate choices:
//  • Sleep is returned as SEGMENTS with their stage and source bundle, not as
//    a single number. Watch and iPhone write overlapping samples for the same
//    night, so only `SleepAnalyzer` (in the core, covered by tests) can decide
//    what "6:03" means. The old whole-day sum double-counted them.
//  • HRV is aggregated as the natural log of the night median, because HRV is
//    log-normal and daytime samples are noisy.
//
//  Nothing here interprets values; it maps HealthKit into `ContextSignal` and
//  `DailyHealthSummary` and stops.
//

import Foundation
import HealthKit

nonisolated final class HealthKitHistoryReader: HealthHistorySource {

    /// `HKHealthStore` is documented as safe to use from any thread; the app
    /// keeps exactly one instance (created by `HealthKitManager`).
    private nonisolated(unsafe) let store: HKHealthStore

    init(store: HKHealthStore) {
        self.store = store
    }

    // MARK: - Today's signals

    /// Raw signals for `window`: sleep segments, HRV samples, resting heart
    /// rate, steps, active energy and workouts.
    func signals(in window: DateInterval, time: TimeContext) async throws -> [ContextSignal] {
        async let sleep = sleepSignals(in: window)
        async let hrv = quantitySignals(.heartRateVariabilitySDNN, kind: .hrvSDNN, unit: HKUnit.secondUnit(with: .milli), unitName: "ms", in: window)
        async let resting = quantitySignals(.restingHeartRate, kind: .restingHeartRate, unit: Self.bpm, unitName: "bpm", in: window)
        async let steps = quantitySignals(.stepCount, kind: .steps, unit: .count(), unitName: "count", in: window)
        async let energy = quantitySignals(.activeEnergyBurned, kind: .activeEnergy, unit: .kilocalorie(), unitName: "kcal", in: window)
        async let workouts = workoutSignals(in: window)
        return try await sleep + hrv + resting + steps + energy + workouts
    }

    /// Sleep segments with their stage and originating app, so the analyzer can
    /// pick one source instead of summing overlapping ones.
    private func sleepSignals(in window: DateInterval) async throws -> [ContextSignal] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: Self.predicate(window))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let samples = try await descriptor.result(for: store)
        return samples.compactMap { sample in
            guard let stage = Self.stage(of: sample) else { return nil }
            return ContextSignal(
                kind: .sleepSegment,
                value: .interval(nil),
                start: sample.startDate,
                end: sample.endDate,
                source: .healthKit,
                attributes: [
                    SignalAttribute.stage: stage.rawValue,
                    SignalAttribute.sourceBundle: sample.sourceRevision.source.bundleIdentifier,
                ]
            )
        }
    }

    private func quantitySignals(
        _ identifier: HKQuantityTypeIdentifier,
        kind: SignalKind,
        unit: HKUnit,
        unitName: String,
        in window: DateInterval
    ) async throws -> [ContextSignal] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: Self.predicate(window))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let samples = try await descriptor.result(for: store)
        return samples.map { sample in
            ContextSignal(
                kind: kind,
                value: .number(sample.quantity.doubleValue(for: unit)),
                start: sample.startDate,
                end: sample.endDate,
                source: .healthKit,
                unit: unitName,
                attributes: [SignalAttribute.sourceBundle: sample.sourceRevision.source.bundleIdentifier]
            )
        }
    }

    private func workoutSignals(in window: DateInterval) async throws -> [ContextSignal] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(Self.predicate(window))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let workouts = try await descriptor.result(for: store)
        return workouts.map { workout in
            let kilocalories = workout
                .statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie())
            return ContextSignal(
                kind: .workout,
                value: .interval(kilocalories),
                start: workout.startDate,
                end: workout.endDate,
                source: .healthKit,
                unit: "kcal",
                attributes: [SignalAttribute.activity: workout.workoutActivityType.displayName]
            )
        }
    }

    // MARK: - History (HealthHistorySource)

    /// Daily aggregates for the `days` local days before `day` (today excluded).
    /// Sleep is attributed to the day the user woke up on.
    func dailySummaries(days: Int, before day: Date, time: TimeContext) async throws -> [DailyHealthSummary] {
        let end = time.startOfDay(day)
        let start = time.adding(days: -days, to: end)
        // Sleep for the first day in the window may start the previous evening.
        let window = DateInterval(start: time.adding(days: -1, to: start), end: end)

        async let sleepSignals = self.sleepSignals(in: window)
        async let hrvSamples = quantitySignals(.heartRateVariabilitySDNN, kind: .hrvSDNN, unit: HKUnit.secondUnit(with: .milli), unitName: "ms", in: window)
        async let restingSamples = quantitySignals(.restingHeartRate, kind: .restingHeartRate, unit: Self.bpm, unitName: "bpm", in: window)
        async let workouts = workoutSignals(in: window)
        async let steps = dailyTotals(.stepCount, unit: .count(), start: start, end: end, time: time)
        async let energy = dailyTotals(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end, time: time)

        let analyzer = SleepAnalyzer()
        let nights = analyzer.nights(signals: try await sleepSignals, time: time)
        let hrv = try await hrvSamples
        let resting = try await restingSamples
        let workoutList = try await workouts
        let stepTotals = try await steps
        let energyTotals = try await energy

        var summaries: [Date: DailyHealthSummary] = [:]
        func row(_ dayStart: Date) -> DailyHealthSummary {
            summaries[dayStart] ?? DailyHealthSummary(day: dayStart)
        }

        for night in nights where night.day >= start && night.day < end {
            var values = row(night.day)
            values[.sleepAsleep] = night.asleepSeconds
            values[.sleepInBed] = night.inBedSeconds
            values[.sleepBedtime] = night.bedtime.timeIntervalSince(night.day) / 60
            summaries[night.day] = values
        }

        // HRV: ln of the night median (00:00–12:00), falling back to the whole day.
        let hrvByDay = Dictionary(grouping: hrv) { time.startOfDay($0.start) }
        for (dayStart, samples) in hrvByDay where dayStart >= start && dayStart < end {
            let noon = time.date(on: dayStart, at: TimeOfDay(hour: 12))
            let night = samples.filter { $0.start < noon }
            let values = (night.isEmpty ? samples : night).compactMap { $0.value.number }
            guard let median = StateMath.median(values), median > 0 else { continue }
            var updated = row(dayStart)
            updated[.hrvLog] = log(median)
            summaries[dayStart] = updated
        }

        // Resting heart rate: the last sample of the day (Apple writes one).
        let restingByDay = Dictionary(grouping: resting) { time.startOfDay($0.start) }
        for (dayStart, samples) in restingByDay where dayStart >= start && dayStart < end {
            guard let last = samples.sorted(by: { $0.start < $1.start }).last?.value.number else { continue }
            var updated = row(dayStart)
            updated[.restingHeartRate] = last
            summaries[dayStart] = updated
        }

        let workoutsByDay = Dictionary(grouping: workoutList) { time.startOfDay($0.start) }
        for (dayStart, dayWorkouts) in workoutsByDay where dayStart >= start && dayStart < end {
            let seconds = dayWorkouts.reduce(TimeInterval.zero) { total, signal in total + signal.duration }
            var updated = row(dayStart)
            updated[.workoutMinutes] = seconds / 60
            summaries[dayStart] = updated
        }

        for (dayStart, total) in stepTotals where dayStart >= start && dayStart < end {
            var updated = row(dayStart)
            updated[.steps] = total
            summaries[dayStart] = updated
        }
        for (dayStart, total) in energyTotals where dayStart >= start && dayStart < end {
            var updated = row(dayStart)
            updated[.activeEnergy] = total
            summaries[dayStart] = updated
        }

        return summaries.values.sorted { $0.day < $1.day }
    }

    /// Per-day cumulative sums via a statistics collection (cheap for counters).
    private func dailyTotals(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date,
        time: TimeContext
    ) async throws -> [Date: Double] {
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier), predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)
        var totals: [Date: Double] = [:]
        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            guard let sum = statistics.sumQuantity() else { return }
            totals[time.startOfDay(statistics.startDate)] = sum.doubleValue(for: unit)
        }
        return totals
    }

    // MARK: - Mapping helpers

    private static let bpm = HKUnit.count().unitDivided(by: .minute())

    private static func predicate(_ window: DateInterval) -> NSPredicate {
        HKQuery.predicateForSamples(withStart: window.start, end: window.end)
    }

    /// Maps HealthKit's sleep category value to the core's stage vocabulary.
    private static func stage(of sample: HKCategorySample) -> SleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .inBed: return .inBed
        case .awake: return .awake
        case .asleepCore: return .core
        case .asleepDeep: return .deep
        case .asleepREM: return .rem
        case .asleepUnspecified: return .unspecified
        default: return nil
        }
    }
}
