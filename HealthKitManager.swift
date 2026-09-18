//
//  HealthKitManager.swift
//  Linea
//
//  Read-only HealthKit integration layer, expanded in Phase 2.
//
//  This is the single boundary between the app and HealthKit — no feature
//  screen touches `HKHealthStore` directly. It is modular: each metric is read
//  by a small, reusable query helper, so adding a new type later is a couple
//  of lines. All access is READ-ONLY; no share/write types are ever requested.
//
//  Metrics: step count · sleep analysis · resting HR · heart rate ·
//  HRV (SDNN) · active energy · walking/running distance · workouts · VO2 Max.
//
//  Чтение параллельное и с таймаутом на каждый запрос. Раньше показатели
//  читались строго по очереди и без ограничения по времени: один зависший
//  запрос оставлял все следующие в состоянии «загружается» навсегда, и экран
//  выглядел так, будто данных нет вовсе. HealthKit не обязан вызывать
//  обработчик — при отказе в доступе он может промолчать.
//
//  The original working step-count proof of concept (availability check →
//  read-only authorization → cumulative-sum statistics query for today) is
//  preserved: see `readTypes`, `connect()`, and `sumToday(_:unit:)`.
//

import Foundation
import HealthKit
import Observation

@Observable
@MainActor
final class HealthKitManager {

    /// Whole-integration authorization / availability state.
    enum AuthState: Equatable {
        case notRequested
        case requesting
        case authorized
        case unavailable
        case failed(message: String)
    }

    private(set) var authState: AuthState = .notRequested

    // MARK: - Per-metric state (never fabricated)

    private(set) var steps: MetricState<Int> = .loading
    private(set) var sleep: MetricState<TimeInterval> = .loading          // seconds asleep
    private(set) var activeEnergy: MetricState<Double> = .loading         // kcal today
    private(set) var distance: MetricState<Double> = .loading             // meters today
    private(set) var restingHeartRate: MetricState<Int> = .loading        // latest bpm
    private(set) var heartRate: MetricState<Int> = .loading               // latest bpm
    private(set) var hrv: MetricState<Double> = .loading                  // latest SDNN, ms
    private(set) var vo2Max: MetricState<Double> = .loading               // latest ml/kg/min
    private(set) var workouts: MetricState<[WorkoutSummary]> = .loading   // today's workouts

    /// Shared with `HealthKitHistoryReader` (the intelligence connector), so the
    /// app keeps exactly one store. Not private for that reason only.
    @ObservationIgnored let healthStore = HKHealthStore()

    /// Reads history and sleep segments for the intelligence core; also used
    /// here for the sleep tile, so both show the same night. Built on demand:
    /// it is a thin wrapper around the store above.
    private var historyReader: HealthKitHistoryReader { HealthKitHistoryReader(store: healthStore) }

    /// The read-only set of types Linea requests. Nothing outside this list is
    /// requested, and no write/share types are requested at all.
    @ObservationIgnored private let readTypes: Set<HKObjectType> = [
        HKQuantityType(.stepCount),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.heartRate),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.vo2Max),
        HKCategoryType(.sleepAnalysis),
        HKObjectType.workoutType()
    ]

    var isAuthorized: Bool { authState == .authorized }

    /// True if any metric currently holds a real value (used to infer that the
    /// user has already granted access in a previous session).
    var hasAnyMetricValue: Bool {
        steps.unwrapped != nil || sleep.unwrapped != nil || activeEnergy.unwrapped != nil
            || distance.unwrapped != nil || restingHeartRate.unwrapped != nil
            || heartRate.unwrapped != nil || hrv.unwrapped != nil || vo2Max.unwrapped != nil
            || (workouts.unwrapped?.isEmpty == false)
    }

    // MARK: - Authorization

    /// Silently reads without prompting. If any real data comes back, we know
    /// access was granted in a previous session and flip to `.authorized`.
    /// If nothing comes back we stay `.notRequested` and show the connect CTA
    /// (we can't distinguish "denied read" from "no data" — see MetricState).
    ///
    /// Once authorized it re-reads on every call. It used to return early in
    /// that case, so the numbers were read once and then stayed frozen for the
    /// whole session — steps taken since morning never appeared.
    func probeExistingAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authState = .unavailable
            return
        }
        if authState == .authorized {
            await refreshAll()
            return
        }
        guard authState == .notRequested else { return }
        await refreshAll()
        if hasAnyMetricValue {
            authState = .authorized
        }
    }

    /// Requests read-only authorization for all supported types, then reads
    /// everything. Safe to call repeatedly — HealthKit only shows the sheet the
    /// first time.
    func connect() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authState = .unavailable
            return
        }
        authState = .requesting
        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            authState = .authorized
            LineaLog.health.notice("Доступ запрошен, читаю данные")
            await refreshAll()
        } catch {
            LineaLog.health.error("Запрос доступа не удался: \(error.localizedDescription, privacy: .public)")
            authState = .failed(message: error.localizedDescription)
        }
    }

    /// Re-reads all metrics without prompting. Assumes access was requested.
    func refreshAll() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authState = .unavailable
            return
        }

        LineaLog.health.notice("Читаю показатели. \(LineaLog.environment(), privacy: .public)")
        let startedAt = Date()

        // Запросы идут одновременно: один медленный больше не задерживает
        // остальные, и ни один не может подвесить экран насовсем.
        async let stepsRead = sumToday(HKQuantityType(.stepCount), unit: .count(), name: "шаги")
        async let energyRead = sumToday(HKQuantityType(.activeEnergyBurned), unit: .kilocalorie(), name: "активная энергия")
        async let distanceRead = sumToday(HKQuantityType(.distanceWalkingRunning), unit: .meter(), name: "дистанция")
        async let restingRead = latest(HKQuantityType(.restingHeartRate), unit: Self.bpm, name: "пульс покоя")
        async let heartRateRead = latest(HKQuantityType(.heartRate), unit: Self.bpm, name: "пульс")
        async let hrvRead = latest(HKQuantityType(.heartRateVariabilitySDNN), unit: HKUnit.secondUnit(with: .milli), name: "HRV")
        async let vo2Read = latest(HKQuantityType(.vo2Max), unit: Self.vo2Unit, name: "VO2 Max")
        async let sleepRead = sleepDuration()
        async let workoutsRead = todaysWorkouts()

        steps = (await stepsRead).mapValue { Int($0.rounded()) }
        activeEnergy = await energyRead
        distance = await distanceRead
        restingHeartRate = (await restingRead).mapValue { Int($0.rounded()) }
        heartRate = (await heartRateRead).mapValue { Int($0.rounded()) }
        hrv = await hrvRead
        vo2Max = await vo2Read
        sleep = await sleepRead
        workouts = await workoutsRead

        let seconds = Date().timeIntervalSince(startedAt)
        LineaLog.health.notice("Прочитано за \(String(format: "%.1f", seconds), privacy: .public) с, значений: \(self.valueCount, privacy: .public) из 9")
    }

    /// Сколько показателей реально пришло — первое, что смотрят в журнале.
    private var valueCount: Int {
        var count = 0
        if steps.unwrapped != nil { count += 1 }
        if sleep.unwrapped != nil { count += 1 }
        if activeEnergy.unwrapped != nil { count += 1 }
        if distance.unwrapped != nil { count += 1 }
        if restingHeartRate.unwrapped != nil { count += 1 }
        if heartRate.unwrapped != nil { count += 1 }
        if hrv.unwrapped != nil { count += 1 }
        if vo2Max.unwrapped != nil { count += 1 }
        if workouts.unwrapped != nil { count += 1 }
        return count
    }

    // MARK: - Query helpers (reusable, modular)

    /// Cumulative sum of a quantity type from the start of today until now.
    private func sumToday(_ type: HKQuantityType, unit: HKUnit, name: String) async -> MetricState<Double> {
        await guarded(name) { await self.readSum(type, unit: unit) }
    }

    private func readSum(_ type: HKQuantityType, unit: HKUnit) async -> MetricState<Double> {
        let (start, end) = Self.todayRange()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                if let sum = statistics?.sumQuantity() {
                    continuation.resume(returning: .value(sum.doubleValue(for: unit)))
                } else {
                    continuation.resume(returning: .noData)
                }
            }
            healthStore.execute(query)
        }
    }

    /// The most recent sample of a quantity type (e.g. latest resting HR).
    private func latest(_ type: HKQuantityType, unit: HKUnit, name: String) async -> MetricState<Double> {
        await guarded(name) { await self.readLatest(type, unit: unit) }
    }

    private func readLatest(_ type: HKQuantityType, unit: HKUnit) async -> MetricState<Double> {
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: sort
            ) { _, samples, _ in
                if let sample = samples?.first as? HKQuantitySample {
                    continuation.resume(returning: .value(sample.quantity.doubleValue(for: unit)))
                } else {
                    continuation.resume(returning: .noData)
                }
            }
            healthStore.execute(query)
        }
    }

    /// Last night's sleep, deduplicated across sources.
    ///
    /// Watch and iPhone write overlapping samples for the same night, so
    /// summing every "asleep" sample (what this used to do) inflated a 6-hour
    /// night to 9-12 hours. `SleepAnalyzer` picks ONE source — stages first,
    /// then the longest — and unions its intervals; the same code the
    /// intelligence core uses, so the tile and the plan never disagree.
    private func sleepDuration() async -> MetricState<TimeInterval> {
        await guarded("сон") { await self.readSleep() }
    }

    private func readSleep() async -> MetricState<TimeInterval> {
        let time = TimeContext.live
        let window = DateInterval(
            start: time.date(on: time.adding(days: -1, to: time.today), at: TimeOfDay(hour: 18)),
            end: time.now
        )
        do {
            let signals = try await historyReader.signals(in: window, time: time)
                .filter { $0.kind == .sleepSegment }
            guard let night = SleepAnalyzer().night(for: time.today, signals: signals, time: time),
                  night.asleepSeconds > 0 else {
                return .noData
            }
            return .value(night.asleepSeconds)
        } catch {
            return .noData
        }
    }

    /// Workouts that started today.
    private func todaysWorkouts() async -> MetricState<[WorkoutSummary]> {
        await guarded("тренировки") { await self.readWorkouts() }
    }

    private func readWorkouts() async -> MetricState<[WorkoutSummary]> {
        let (start, end) = Self.todayRange()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { _, samples, _ in
                guard let workouts = samples as? [HKWorkout], !workouts.isEmpty else {
                    continuation.resume(returning: .noData)
                    return
                }
                let summaries = workouts.map { workout in
                    WorkoutSummary(
                        id: workout.uuid,
                        activity: workout.workoutActivityType.displayName,
                        duration: workout.duration,
                        energyKilocalories: workout
                            .statistics(for: HKQuantityType(.activeEnergyBurned))?
                            .sumQuantity()?
                            .doubleValue(for: .kilocalorie()),
                        start: workout.startDate
                    )
                }
                continuation.resume(returning: .value(summaries))
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Таймаут и журнал

    /// Сколько ждём один запрос, прежде чем считать, что ответа не будет.
    private static let queryTimeout = Duration.seconds(8)

    /// Выполняет чтение с ограничением по времени и пишет результат в журнал.
    /// HealthKit не гарантирует вызов обработчика: при отказе в доступе он
    /// может просто промолчать, и без таймаута показатель висел бы вечно.
    private func guarded<T: Equatable & Sendable>(
        _ name: String,
        _ read: @escaping @Sendable () async -> MetricState<T>
    ) async -> MetricState<T> {
        let startedAt = Date()
        let result: MetricState<T>? = await withTaskGroup(of: MetricState<T>?.self) { group in
            group.addTask { await read() }
            group.addTask {
                try? await Task.sleep(for: Self.queryTimeout)
                return nil
            }
            let winner = await group.next() ?? nil
            group.cancelAll()
            return winner
        }

        let seconds = Date().timeIntervalSince(startedAt)
        guard let result else {
            LineaLog.health.error("\(name, privacy: .public): нет ответа за \(String(format: "%.1f", seconds), privacy: .public) с")
            return .noData
        }
        switch result {
        case .value:
            LineaLog.health.info("\(name, privacy: .public): есть значение (\(String(format: "%.2f", seconds), privacy: .public) с)")
        case .noData:
            LineaLog.health.notice("\(name, privacy: .public): данных нет — доступ закрыт или записей нет")
        case .loading:
            break
        }
        return result
    }

    // MARK: - Units & ranges

    private static let bpm = HKUnit.count().unitDivided(by: .minute())
    private static let vo2Unit = HKUnit(from: "ml/kg*min")

    private static func todayRange() -> (Date, Date) {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        return (start, now)
    }
}
