//
//  SleepInsight.swift
//  Linea
//
//  «Аналитика сна» — отдельный юзкейс из брифа: не одно число за сегодня, а
//  как человек спит последнюю неделю относительно собственной нормы.
//
//  Всё считается из тех же дневных сводок, что и baseline, поэтому экран
//  Health и утренний план никогда не расходятся в цифрах. Если данных мало,
//  структура честно говорит об этом (`baselineProgress`), а не подставляет
//  популяционные нормы.
//

import Foundation

nonisolated struct SleepInsight: Sendable, Hashable {
    /// Ночи за последнюю неделю, от старых к новым.
    let recentNights: [DailyNight]
    /// Средний сон за последние 7 дней с данными, секунды.
    let weekAverageSeconds: TimeInterval?
    /// Личная норма (медиана за окно baseline), секунды.
    let usualSeconds: TimeInterval?
    /// Разница «неделя минус норма», секунды. Отрицательная — спал меньше.
    let deltaSeconds: TimeInterval?
    /// Разброс времени отхода ко сну (MAD), минуты. Меньше — стабильнее.
    let bedtimeStabilityMinutes: Double?
    /// Средняя эффективность сна за неделю (доля сна от времени в кровати).
    let weekEfficiency: Double?
    /// Сколько дней истории собрано и сколько нужно для сравнений.
    let baselineProgress: BaselineProgress?

    /// Есть ли надёжная личная норма, с которой можно сравнивать вслух.
    var canCompare: Bool { usualSeconds != nil && baselineProgress?.isComplete != false }

    nonisolated struct DailyNight: Sendable, Hashable {
        let day: Date
        let asleepSeconds: TimeInterval
        let inBedSeconds: TimeInterval?
        /// Минуты от полуночи; отрицательные — отбой до полуночи.
        let bedtimeMinutes: Double?

        var efficiency: Double? {
            guard let inBedSeconds, inBedSeconds > 0 else { return nil }
            return min(asleepSeconds / inBedSeconds, 1)
        }
    }

    static let empty = SleepInsight(
        recentNights: [], weekAverageSeconds: nil, usualSeconds: nil, deltaSeconds: nil,
        bedtimeStabilityMinutes: nil, weekEfficiency: nil, baselineProgress: nil
    )
}

nonisolated struct SleepInsightBuilder: Sendable {
    var recentDays: Int
    var calculator: BaselineCalculator

    init(recentDays: Int = 7, calculator: BaselineCalculator = BaselineCalculator()) {
        self.recentDays = recentDays
        self.calculator = calculator
    }

    /// `history` — дневные сводки (сегодня может входить, но в норму не идёт),
    /// `today` — сегодняшняя ночь, если она уже прочитана.
    func build(history: [DailyHealthSummary], today: DailyHealthSummary?, config: EngineConfig, time: TimeContext) -> SleepInsight {
        var rows: [Date: DailyHealthSummary] = [:]
        for summary in history where summary[.sleepAsleep] != nil {
            rows[time.startOfDay(summary.day)] = summary
        }
        if let today, today[.sleepAsleep] != nil {
            rows[time.startOfDay(today.day)] = today
        }
        guard !rows.isEmpty else { return .empty }

        let nights = rows.keys.sorted().compactMap { day -> SleepInsight.DailyNight? in
            guard let asleep = rows[day]?[.sleepAsleep] else { return nil }
            return SleepInsight.DailyNight(
                day: day,
                asleepSeconds: asleep,
                inBedSeconds: rows[day]?[.sleepInBed],
                bedtimeMinutes: rows[day]?[.sleepBedtime]
            )
        }
        let recent = Array(nights.suffix(recentDays))

        // Норма считается по истории БЕЗ сегодняшнего дня — сегодня и есть то,
        // что с ней сравнивают.
        let baselines = calculator.compute(history: history, config: config, time: time)
        let usual = baselines[.sleepAsleep]?.median
        let progress = baselines[.sleepAsleep].map {
            BaselineProgress(days: $0.sampleCount, needed: Baseline.reliableSampleCount)
        } ?? BaselineProgress(days: 0, needed: Baseline.reliableSampleCount)

        let weekAverage = recent.isEmpty ? nil : recent.reduce(0) { $0 + $1.asleepSeconds } / Double(recent.count)
        let bedtimes = recent.compactMap(\.bedtimeMinutes)
        let stability: Double? = {
            guard bedtimes.count >= 3, let median = StateMath.median(bedtimes) else { return nil }
            return StateMath.mad(bedtimes, center: median)
        }()
        let efficiencies = recent.compactMap(\.efficiency)
        let efficiency = efficiencies.isEmpty ? nil : efficiencies.reduce(0, +) / Double(efficiencies.count)

        return SleepInsight(
            recentNights: recent,
            weekAverageSeconds: weekAverage,
            usualSeconds: usual,
            deltaSeconds: (weekAverage != nil && usual != nil) ? weekAverage! - usual! : nil,
            bedtimeStabilityMinutes: stability,
            weekEfficiency: efficiency,
            baselineProgress: progress
        )
    }
}
