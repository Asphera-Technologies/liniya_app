//
//  TimeContext.swift
//  Linea
//
//  The single source of "now", calendar and locale for the intelligence core.
//  Engines never call `Date()` / `Calendar.current` (see Scripts/check-layers.sh):
//  the Docker test container runs in UTC while the user's phone does not, so
//  every calculation takes an explicit `TimeContext`. `TimeContext.live` is
//  created only in the app's composition root.
//

import Foundation

/// A wall-clock time of day (e.g. 09:00) independent of a concrete date.
nonisolated struct TimeOfDay: Codable, Hashable, Sendable, Comparable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }

    var minutesSinceMidnight: Int { hour * 60 + minute }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

nonisolated struct TimeContext: Sendable {
    /// The current moment.
    var now: Date
    /// Calendar with an EXPLICIT time zone (never `Calendar.current`).
    var calendar: Calendar
    /// Locale used for formatting user-facing text.
    var locale: Locale

    init(now: Date, calendar: Calendar, locale: Locale = Locale(identifier: "ru_RU")) {
        self.now = now
        self.calendar = calendar
        self.locale = locale
    }

    /// Convenience: a context in the given IANA time zone.
    init(now: Date, timeZoneIdentifier: String, locale: Locale = Locale(identifier: "ru_RU")) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        calendar.locale = locale
        calendar.firstWeekday = 2
        self.init(now: now, calendar: calendar, locale: locale)
    }

    var timeZone: TimeZone { calendar.timeZone }

    /// Start of the current local day.
    var today: Date { calendar.startOfDay(for: now) }

    func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    /// The local day containing `date`, as a `DateInterval`.
    func dayInterval(containing date: Date) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    /// A concrete moment on the given day at the given wall-clock time.
    func date(on day: Date, at time: TimeOfDay) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: DateComponents(hour: time.hour, minute: time.minute), to: start)
            ?? start.addingTimeInterval(TimeInterval(time.minutesSinceMidnight * 60))
    }

    func timeOfDay(of date: Date) -> TimeOfDay {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
    }

    /// Local hour as a fraction (14:30 → 14.5). Used by the circadian curve.
    func hourFraction(of date: Date) -> Double {
        let comps = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60 + Double(comps.second ?? 0) / 3600
    }

    func isSameDay(_ a: Date, _ b: Date) -> Bool { calendar.isDate(a, inSameDayAs: b) }

    func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(Double(days) * 86_400)
    }

    /// Whole days between two dates' local midnights (positive if `to` is later).
    func days(from: Date, to: Date) -> Int {
        calendar.dateComponents([.day], from: startOfDay(from), to: startOfDay(to)).day ?? 0
    }

    /// A copy of this context moved to another moment.
    func at(_ moment: Date) -> TimeContext {
        TimeContext(now: moment, calendar: calendar, locale: locale)
    }
}
