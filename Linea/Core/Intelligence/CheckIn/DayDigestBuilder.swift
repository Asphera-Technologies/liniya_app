//
//  DayDigestBuilder.swift
//  Linea
//
//  Выжимка дня — одна строка вместо пятиминутного рассказа. Именно она, а не
//  сырой текст, попадает в следующие запросы к модели: день из дневника
//  стоит десятки токенов, а не тысячи. Собирается детерминированно из
//  подтверждённого итога, поэтому в ней нет ничего, чего человек не видел.
//

import Foundation

nonisolated struct DayDigestBuilder: Sendable {
    /// Сколько названий перечислять в одном списке.
    var maxTitles: Int
    var maxTitleLength: Int

    init(maxTitles: Int = 4, maxTitleLength: Int = 32) {
        self.maxTitles = maxTitles
        self.maxTitleLength = maxTitleLength
    }

    static let weekdays = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]

    /// «22.09, пн»
    static func dayLabel(_ day: Date, time: TimeContext) -> String {
        let components = time.calendar.dateComponents([.day, .month, .weekday], from: day)
        let weekday = weekdays[((components.weekday ?? 1) - 1 + 7) % 7]
        return String(format: "%02d.%02d", components.day ?? 0, components.month ?? 0) + ", " + weekday
    }

    /// Полная выжимка: итоги, названия, оценка и фраза модели.
    func digest(for report: CheckInReport, day: Date, time: TimeContext) -> String {
        var text = headline(for: report, day: day, time: time)
        if !report.completed.isEmpty { text += " Сделано: \(titles(report.completed.map(\.title)))." }
        let unfinished = report.unfinished.filter { $0.status != .done }
        if !unfinished.isEmpty { text += " Не сделано: \(titles(unfinished.map(\.title)))." }
        if !report.extra.isEmpty { text += " Ещё: \(titles(report.extra.map(\.title)))." }
        if let summary = report.summary, !summary.isEmpty {
            text += " " + (summary.hasSuffix(".") ? summary : summary + ".")
        }
        return text
    }

    /// Короткая выжимка для старых дней: только цифры и оценка.
    func headline(for report: CheckInReport, day: Date, time: TimeContext) -> String {
        "\(Self.dayLabel(day, time: time)): \(numbers(for: report))."
    }

    /// Цифры дня без даты: «сделано 3 из 5, работа 7 ч, день: тяжело».
    func numbers(for report: CheckInReport) -> String {
        var parts: [String] = []
        let done = report.completed.count
        if report.plannedCount > 0 {
            parts.append("сделано \(report.completedPlannedCount) из \(report.plannedCount)")
            let beyond = done - report.completedPlannedCount
            if beyond > 0 { parts.append("сверх плана \(beyond)") }
        } else if done > 0 {
            parts.append("сделано задач: \(done)")
        }
        if let minutes = report.workMinutes {
            parts.append("работа \(report.isWorkStated ? "" : "≈")\(RussianText.duration(minutes: minutes))")
        }
        if let rating = report.rating { parts.append("день: \(rating.title.lowercased())") }
        if let energy = report.energy { parts.append(energy.title) }
        return parts.isEmpty ? "итог без подробностей" : parts.joined(separator: ", ")
    }

    private func titles(_ titles: [String]) -> String {
        let shown = titles.prefix(maxTitles).map { title -> String in
            let trimmed = title.count > maxTitleLength ? String(title.prefix(maxTitleLength - 1)) + "…" : title
            return RussianText.quoted(trimmed)
        }
        let rest = titles.count - shown.count
        return shown.joined(separator: ", ") + (rest > 0 ? " и ещё \(rest)" : "")
    }
}
