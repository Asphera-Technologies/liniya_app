//
//  FeedbackEngine.swift
//  Linea
//
//  What Linea learns from «Отлично / Нормально / Тяжело».
//
//  Three buttons a day cannot identify five scoring weights, so the weights
//  are never touched — they are logged instead. What does move is a small set
//  of bounded knobs: how strict the energy verdict is, how much the day can
//  hold, and how patient the nudges are.
//
//  Calibration is recomputed from history every time rather than nudged
//  incrementally: the same history always yields the same profile, so a
//  double-processed rating cannot drift the model.
//

import Foundation

nonisolated struct FeedbackEngine: Sendable {
    let config: EngineConfig
    /// How far back ratings are taken into account.
    var windowDays: Int
    /// EMA weight of the newest rating for the energy bias.
    var biasSmoothing: Double
    /// Ratings are only trusted to calibrate when the state was confident.
    var minimumStateConfidence: Double

    init(config: EngineConfig = .default, windowDays: Int = 14, biasSmoothing: Double = 0.3, minimumStateConfidence: Double = 0.5) {
        self.config = config
        self.windowDays = windowDays
        self.biasSmoothing = biasSmoothing
        self.minimumStateConfidence = minimumStateConfidence
    }

    func calibrate(history: [DayRecord], previous: Calibration, time: TimeContext) -> Calibration {
        let windowStart = time.adding(days: -windowDays, to: time.today)
        let days = history
            .filter { $0.day >= windowStart }
            .sorted { $0.day < $1.day }

        var result = Calibration.default
        result.changeLog = previous.changeLog

        let rated = days.compactMap { record -> (record: DayRecord, rating: DayRating)? in
            guard let rating = record.rating else { return nil }
            return (record, rating)
        }

        result.energyBias = energyBias(rated)
        let thresholds = thresholds(rated)
        result.reduceThreshold = thresholds.reduce
        result.pushThreshold = thresholds.push
        result.capacityFactor = capacityFactor(days)
        result.estimateMultiplier = previous.estimateMultiplier   // needs real durations; see Docs/open-questions.md
        result.nudgeGraceMinutes = nudgeGrace(days)
        result.nudgeCooldownMultiplier = nudgeCooldown(days)
        result.ratingsCount = rated.count
        result.lastRatingAppliedDay = rated.last?.record.day
        result.changeLog = log(from: previous, to: result, at: time.now)
        return result
    }

    // MARK: Knobs

    /// Did the day feel like the model predicted? If «Тяжело» keeps landing on
    /// days Linea called good, it is Linea that is wrong.
    private func energyBias(_ rated: [(record: DayRecord, rating: DayRating)]) -> Double {
        var bias = 0.0
        for entry in rated {
            guard let state = entry.record.state, state.confidence >= minimumStateConfidence else { continue }
            let predicted: Double = state.energy >= 0.65 ? 1 : (state.energy <= 0.40 ? -1 : 0)
            let residual = entry.rating.value - predicted
            bias = (1 - biasSmoothing) * bias + biasSmoothing * 0.05 * residual
        }
        return min(max(bias, -0.15), 0.15)
    }

    /// Thresholds move only when the same mistake repeats: twice in the last
    /// three comparable days. One bad Tuesday is not a pattern.
    private func thresholds(_ rated: [(record: DayRecord, rating: DayRating)]) -> (reduce: Double, push: Double) {
        var reduce = Calibration.default.reduceThreshold
        var push = Calibration.default.pushThreshold

        func repeats(_ matches: (DayRecord, DayRating) -> Bool, among advice: (LoadAdvice) -> Bool) -> Bool {
            let comparable = rated.filter { entry in
                guard let state = entry.record.state else { return false }
                return advice(state.loadAdvice)
            }
            let recent = comparable.suffix(3)
            guard recent.count >= 2 else { return false }
            return recent.filter { matches($0.record, $0.rating) }.count >= 2
        }

        let hardWhenPushing = repeats({ _, rating in rating == .hard }, among: { $0 == .push })
        if hardWhenPushing { push = min(push + 0.03, 0.85) }

        let hardWhenNormal = repeats({ _, rating in rating == .hard }, among: { $0 == .normal })
        if hardWhenNormal { reduce = min(reduce + 0.02, 0.55) }

        let greatWhenReducing = repeats({ _, rating in rating == .great }, among: { $0 == .reduce })
        if greatWhenReducing { reduce = max(reduce - 0.03, 0.30) }

        return (reduce, push)
    }

    /// How much of the free time a day may actually be filled with.
    ///
    /// When the user told Linea how the day went (the check-in), the real
    /// share of the plan that happened drives it: someone who closes two
    /// thirds of the plan day after day gets lighter plans. Without a
    /// check-in the evening rating stands in as a proxy.
    private func capacityFactor(_ days: [DayRecord]) -> Double {
        var factor = Calibration.default.capacityFactor
        for record in days {
            guard let plan = record.plan, !plan.focusBlocks.isEmpty else { continue }
            let plannedMinutes = plan.focusBlocks.reduce(0) { $0 + $1.durationMinutes }
            guard plannedMinutes >= 30 else { continue }
            let ratio: Double
            if let completion = record.report?.completionRatio {
                // One disastrous day must not halve tomorrow's plan.
                ratio = min(max(completion, 0.4), 1.1)
            } else if let rating = record.rating {
                switch rating {
                case .great: ratio = 1.0
                case .ok: ratio = 0.85
                case .hard: ratio = 0.6
                }
            } else {
                continue
            }
            factor = 0.8 * factor + 0.2 * ratio
        }
        return min(max(factor, 0.5), 1.1)
    }

    /// Someone who keeps postponing wants a longer leash, not more nudges.
    private func nudgeGrace(_ days: [DayRecord]) -> Int {
        var postponed = 0
        var answered = 0
        for record in days {
            for feedback in record.feedback {
                switch feedback.kind {
                case .taskPostponed:
                    postponed += 1
                    answered += 1
                case .nudgeResponse(_, let response):
                    answered += 1
                    if response == .deferred { postponed += 1 }
                default:
                    continue
                }
            }
        }
        guard answered >= 3 else { return Calibration.default.nudgeGraceMinutes }
        return Double(postponed) / Double(answered) > 0.5 ? 30 : Calibration.default.nudgeGraceMinutes
    }

    /// Two dismissals in a row mean «not now» — Linea backs off.
    private func nudgeCooldown(_ days: [DayRecord]) -> Double {
        let responses = days
            .flatMap(\.feedback)
            .sorted { $0.at < $1.at }
            .compactMap { feedback -> NudgeResponse? in
                if case .nudgeResponse(_, let response) = feedback.kind { return response }
                return nil
            }
        let lastTwo = responses.suffix(2)
        return lastTwo.count == 2 && lastTwo.allSatisfy { $0 == .dismissed } ? 2.0 : 1.0
    }

    // MARK: Change log

    private func log(from previous: Calibration, to result: Calibration, at moment: Date) -> [CalibrationChange] {
        var entries = previous.changeLog
        func record(_ parameter: String, _ from: Double, _ to: Double, _ reason: String) {
            guard abs(from - to) > 1e-9 else { return }
            entries.append(CalibrationChange(at: moment, parameter: parameter, from: from, to: to, reason: reason))
        }
        record("energyBias", previous.energyBias, result.energyBias, "Оценки дня разошлись с моей оценкой сил.")
        record("reduceThreshold", previous.reduceThreshold, result.reduceThreshold,
               "Порог «снизить нагрузку» подстроен под твои вечерние оценки.")
        record("pushThreshold", previous.pushThreshold, result.pushThreshold,
               "Порог «можно больше» подстроен под твои вечерние оценки.")
        record("capacityFactor", previous.capacityFactor, result.capacityFactor,
               "Изменил, сколько работы помещается в день — по тому, сколько плана получается сделать.")
        record("nudgeGraceMinutes", Double(previous.nudgeGraceMinutes), Double(result.nudgeGraceMinutes),
               "Изменил паузу перед напоминанием.")
        record("nudgeCooldownMultiplier", previous.nudgeCooldownMultiplier, result.nudgeCooldownMultiplier,
               "Изменил, как часто напоминаю.")
        // Keep the log readable: the screen shows the last few entries anyway.
        return Array(entries.suffix(50))
    }
}
