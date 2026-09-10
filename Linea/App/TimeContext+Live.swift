//
//  TimeContext+Live.swift
//  Linea
//
//  The one place where "now" enters the app. Everything below the App layer
//  receives a `TimeContext`; engines never read the ambient clock, which is
//  what makes the morning brief and the 14:30 nudge reproducible in tests.
//

import Foundation

extension TimeContext {
    /// The user's real clock, calendar and locale.
    static var live: TimeContext {
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = Locale(identifier: "ru_RU")
        return TimeContext(now: Date(), calendar: calendar, locale: Locale(identifier: "ru_RU"))
    }
}
