//
//  UserProfile.swift
//  Linea
//
//  The little Linea needs to know about the person to define «доступное время
//  сегодня»: working day, quiet hours, when to ask how the day went. One
//  record, editable from Profile; defaults make the engines work before
//  onboarding is finished.
//

import Foundation

nonisolated struct UserProfile: Codable, Hashable, Sendable {
    static let schemaVersion = 1

    var name: String?
    /// Planning window of the day.
    var workdayStart: TimeOfDay
    var workdayEnd: TimeOfDay
    /// No nudges between these (spanning midnight).
    var quietHoursStart: TimeOfDay
    var quietHoursEnd: TimeOfDay
    /// When «Как прошёл день?» becomes available.
    var eveningCheckIn: TimeOfDay
    /// Target sleep used before a personal baseline exists.
    var sleepNeedSeconds: TimeInterval
    var onboardingCompleted: Bool

    init(
        name: String? = nil,
        workdayStart: TimeOfDay = TimeOfDay(hour: 9),
        workdayEnd: TimeOfDay = TimeOfDay(hour: 21),
        quietHoursStart: TimeOfDay = TimeOfDay(hour: 22),
        quietHoursEnd: TimeOfDay = TimeOfDay(hour: 8),
        eveningCheckIn: TimeOfDay = TimeOfDay(hour: 20, minute: 30),
        sleepNeedSeconds: TimeInterval = 7.5 * 3600,
        onboardingCompleted: Bool = false
    ) {
        self.name = name
        self.workdayStart = workdayStart
        self.workdayEnd = workdayEnd
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.eveningCheckIn = eveningCheckIn
        self.sleepNeedSeconds = sleepNeedSeconds
        self.onboardingCompleted = onboardingCompleted
    }

    static let `default` = UserProfile()

    /// True if `time` falls inside quiet hours (which may span midnight).
    func isQuiet(_ time: TimeOfDay) -> Bool {
        if quietHoursStart <= quietHoursEnd {
            return time >= quietHoursStart && time < quietHoursEnd
        }
        return time >= quietHoursStart || time < quietHoursEnd
    }
}
