//
//  SleepContextText.swift
//  Linea
//
//  Сон словами — для Linea AI. Модели уходит не одно число «спал 6:40», а
//  то, что Linea уже знает о ночи: когда лёг и встал, фазы, пробуждения,
//  эффективность, собственная оценка сна и неделя относительно нормы. Только
//  посчитанные итоги, ни одного сырого замера HealthKit.
//
//  Если фаз нет (iPhone без часов пишет только «в кровати»), так и
//  говорится: модель не должна их придумывать.
//

import Foundation

nonisolated enum SleepContextText {

    /// Строки контекста для модели. Пусто — о сне ничего не известно.
    static func contextLines(
        night: SleepNight?,
        component: StateComponent?,
        insight: SleepInsight,
        time: TimeContext
    ) -> [String] {
        var lines: [String] = []
        if let night {
            lines.append(nightLine(night, time: time))
            lines.append(stagesLine(night))
        }
        if let component, let score = scoreLine(component) { lines.append(score) }
        lines.append(contentsOf: weekLines(insight, time: time))
        return lines
    }

    /// Ответ без модели: прошлая ночь с фазами и неделя. nil — данных о сне нет.
    static func answer(night: SleepNight?, insight: SleepInsight, time: TimeContext) -> String? {
        var parts: [String] = []
        if let night {
            parts.append("Прошлой ночью — \(duration(night.asleepSeconds)), с \(RussianText.clock(night.bedtime, time: time)) до \(RussianText.clock(night.wakeTime, time: time)).")
            let staged = stagedParts(night, names: [(.deep, "глубокий"), (.rem, "быстрый"), (.core, "базовый")], withShares: false)
            if !staged.isEmpty {
                parts.append("Фазы: \(staged.joined(separator: ", ")).")
            }
        }
        if let average = insight.weekAverageSeconds {
            parts.append("За неделю в среднем \(duration(average)).")
            if insight.canCompare, let usual = insight.usualSeconds {
                parts.append("Обычно \(duration(usual)).")
            } else if let progress = insight.baselineProgress, !progress.isComplete {
                parts.append("Собираю базу: день \(progress.days) из \(progress.needed).")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: Ночь

    /// «Сон прошлой ночью: 6 ч 40 мин, с 23:50 до 7:10; в кровати 7 ч 20 мин;
    /// эффективность 91%; пробуждений: 2.»
    static func nightLine(_ night: SleepNight, time: TimeContext) -> String {
        var parts = ["\(duration(night.asleepSeconds)), с \(RussianText.clock(night.bedtime, time: time)) до \(RussianText.clock(night.wakeTime, time: time))"]
        parts.append("в кровати \(duration(night.inBedSeconds))")
        // У ночи «только в кровати» сон — оценка от времени в кровати, и
        // эффективность из неё ничего не говорит.
        if night.quality >= 0.6, let efficiency = night.efficiency {
            parts.append("эффективность \(percent(efficiency))")
        }
        parts.append("пробуждений: \(night.awakenings)")
        var text = "Сон прошлой ночью: " + parts.joined(separator: "; ") + "."
        if night.quality < 0.6 {
            text += " Сон оценён по времени в кровати: источник не отличает сон от бодрствования."
        }
        return text
    }

    /// «Фазы сна: глубокий 1 ч 5 мин (16%), быстрый (REM) 1 ч 30 мин (22%),
    /// базовый 4 ч 5 мин (62%); бодрствование ночью 15 мин.» Доли — от сна
    /// по фазам. Фаз нет — так и сказано.
    static func stagesLine(_ night: SleepNight) -> String {
        let staged = stagedParts(night, names: [(.deep, "глубокий"), (.rem, "быстрый (REM)"), (.core, "базовый")], withShares: true)
        guard !staged.isEmpty else {
            return "Фаз сна в данных нет: источник записывает только время сна, без фаз."
        }
        var text = "Фазы сна: " + staged.joined(separator: ", ")
        if let awake = night.stages[.awake], awake >= 60 {
            text += "; бодрствование ночью \(duration(awake))"
        }
        return text + "."
    }

    // MARK: Оценка

    /// «Оценка сна Linea: 72 из 100 (…); ниже обычного.» Оценка — компонент
    /// сна из движка состояния: длительность к норме, эффективность, недосып.
    static func scoreLine(_ component: StateComponent) -> String? {
        guard component.kind == .sleep else { return nil }
        let score = Int((component.score * 100).rounded())
        var text = "Оценка сна Linea: \(score) из 100 (длительность относительно нормы, эффективность и недосып за неделю)"
        switch component.level {
        case .belowUsual: text += "; ниже обычного"
        case .usual: text += "; как обычно"
        case .aboveUsual: text += "; выше обычного"
        case .unknown: break
        }
        return text + "."
    }

    // MARK: Неделя

    static func weekLines(_ insight: SleepInsight, time: TimeContext) -> [String] {
        guard let average = insight.weekAverageSeconds else { return [] }
        var parts = ["за неделю в среднем \(duration(average))"]
        if insight.canCompare, let usual = insight.usualSeconds {
            parts.append("обычно \(duration(usual))")
        } else if let progress = insight.baselineProgress, !progress.isComplete {
            parts.append("личная норма ещё собирается: \(progress.days) из \(progress.needed) ночей")
        }
        if let efficiency = insight.weekEfficiency {
            parts.append("средняя эффективность \(percent(efficiency))")
        }
        if let stability = insight.bedtimeStabilityMinutes {
            parts.append("время отбоя гуляет в пределах ±\(Int(stability.rounded())) мин")
        }
        var lines = ["Сон " + parts.joined(separator: ", ") + "."]
        if !insight.recentNights.isEmpty {
            let nights = insight.recentNights.map { "\(RussianText.shortDay($0.day, time: time)) — \(duration($0.asleepSeconds))" }
            lines.append("Ночи за неделю: \(nights.joined(separator: "; ")).")
        }
        return lines
    }

    // MARK: Помощники

    private static func stagedParts(_ night: SleepNight, names: [(SleepStage, String)], withShares: Bool) -> [String] {
        let total = names.reduce(0) { $0 + (night.stages[$1.0] ?? 0) }
        guard total > 0 else { return [] }
        return names.compactMap { stage, name in
            guard let seconds = night.stages[stage], seconds >= 60 else { return nil }
            return withShares ? "\(name) \(duration(seconds)) (\(percent(seconds / total)))" : "\(name) \(duration(seconds))"
        }
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        RussianText.duration(minutes: Int((max(0, seconds) / 60).rounded()))
    }

    private static func percent(_ ratio: Double) -> String {
        "\(Int((min(max(ratio, 0), 1) * 100).rounded()))%"
    }
}
