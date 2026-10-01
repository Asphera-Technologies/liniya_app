//
//  RussianText.swift
//  Linea
//
//  Russian formatting for everything the user reads. Deliberately hand-written
//  instead of `DateFormatter`: the core is tested on Linux, where ICU data for
//  ru_RU can differ from the phone's, and a golden test must mean the same
//  thing in both places.
//

import Foundation

nonisolated enum RussianText {

    /// «Доброе утро» / «Добрый день» / «Добрый вечер» / «Доброй ночи».
    static func greeting(hour: Int) -> String {
        switch hour {
        case 5...11: return "Доброе утро"
        case 12...17: return "Добрый день"
        case 18...22: return "Добрый вечер"
        default: return "Доброй ночи"
        }
    }

    /// «6:03» — hours and minutes of a duration.
    static func hoursMinutes(seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        return String(format: "%d:%02d", total / 3600, (total % 3600) / 60)
    }

    /// «1 ч 20 мин», «45 мин», «2 ч».
    static func duration(minutes: Int) -> String {
        let value = max(0, minutes)
        let hours = value / 60
        let rest = value % 60
        if hours == 0 { return "\(rest) мин" }
        if rest == 0 { return "\(hours) ч" }
        return "\(hours) ч \(rest) мин"
    }

    /// «12:00» — wall-clock time of a moment in the user's calendar.
    static func clock(_ date: Date, time: TimeContext) -> String {
        let value = time.timeOfDay(of: date)
        return String(format: "%d:%02d", value.hour, value.minute)
    }

    /// «1 приоритетное действие» / «3 приоритетных действия» / «5 приоритетных действий».
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let value = abs(n)
        let lastTwo = value % 100
        if (11...14).contains(lastTwo) { return many }
        switch value % 10 {
        case 1: return one
        case 2, 3, 4: return few
        default: return many
        }
    }

    /// Task titles are always quoted, so a title with its own punctuation
    /// cannot be mistaken for Linea's own words.
    static func quoted(_ title: String) -> String { "«\(title)»" }

    /// Календарный день недели (1 — воскресенье … 7 — суббота) → «Пн».
    static let weekdaysShort = ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]
    static let monthsShort = ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]

    /// «Пт, 3 окт»; день другого года — «Пт, 3 янв 2027».
    static func shortDay(_ date: Date, time: TimeContext) -> String {
        let parts = time.calendar.dateComponents([.weekday, .day, .month, .year], from: date)
        let weekday = weekdaysShort[((parts.weekday ?? 1) - 1 + 7) % 7]
        let month = monthsShort[((parts.month ?? 1) - 1 + 12) % 12]
        var text = "\(weekday), \(parts.day ?? 1) \(month)"
        if let year = parts.year, year != time.calendar.component(.year, from: time.now) {
            text += " \(year)"
        }
        return text
    }
}
