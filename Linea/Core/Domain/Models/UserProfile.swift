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
    /// Whether the calendar connector is switched on. Access is asked for in
    /// Profile, not in the middle of a refresh.
    var isCalendarEnabled: Bool
    /// Разрешил ли пользователь облачного ассистента. Пока выключен, наружу
    /// не уходит ничего: тексты собираются шаблонами на устройстве.
    var isCloudAssistantEnabled: Bool
    /// Разрешил ли пользователь отдавать итог дня облачной модели: запись
    /// распознаёт и текст разбирает Grok. Выключено — голос распознаёт
    /// телефон, рассказ разбирают правила, наружу не уходит ничего.
    var isCloudCheckInEnabled: Bool

    init(
        name: String? = nil,
        workdayStart: TimeOfDay = TimeOfDay(hour: 9),
        workdayEnd: TimeOfDay = TimeOfDay(hour: 21),
        quietHoursStart: TimeOfDay = TimeOfDay(hour: 22),
        quietHoursEnd: TimeOfDay = TimeOfDay(hour: 8),
        eveningCheckIn: TimeOfDay = TimeOfDay(hour: 20, minute: 30),
        sleepNeedSeconds: TimeInterval = 7.5 * 3600,
        onboardingCompleted: Bool = false,
        isCalendarEnabled: Bool = false,
        isCloudAssistantEnabled: Bool = false,
        isCloudCheckInEnabled: Bool = false
    ) {
        self.name = name
        self.workdayStart = workdayStart
        self.workdayEnd = workdayEnd
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.eveningCheckIn = eveningCheckIn
        self.sleepNeedSeconds = sleepNeedSeconds
        self.onboardingCompleted = onboardingCompleted
        self.isCalendarEnabled = isCalendarEnabled
        self.isCloudAssistantEnabled = isCloudAssistantEnabled
        self.isCloudCheckInEnabled = isCloudCheckInEnabled
    }

    /// Decoded leniently: this profile is stored as a JSON document, and a
    /// build that adds a field must still be able to read what an older build
    /// wrote. Swift's synthesized decoder would throw on a missing key, which
    /// would silently reset the user's settings.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = UserProfile()
        name = try container.decodeIfPresent(String.self, forKey: .name)
        workdayStart = try container.decodeIfPresent(TimeOfDay.self, forKey: .workdayStart) ?? fallback.workdayStart
        workdayEnd = try container.decodeIfPresent(TimeOfDay.self, forKey: .workdayEnd) ?? fallback.workdayEnd
        quietHoursStart = try container.decodeIfPresent(TimeOfDay.self, forKey: .quietHoursStart) ?? fallback.quietHoursStart
        quietHoursEnd = try container.decodeIfPresent(TimeOfDay.self, forKey: .quietHoursEnd) ?? fallback.quietHoursEnd
        eveningCheckIn = try container.decodeIfPresent(TimeOfDay.self, forKey: .eveningCheckIn) ?? fallback.eveningCheckIn
        sleepNeedSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .sleepNeedSeconds) ?? fallback.sleepNeedSeconds
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? fallback.onboardingCompleted
        isCalendarEnabled = try container.decodeIfPresent(Bool.self, forKey: .isCalendarEnabled) ?? fallback.isCalendarEnabled
        isCloudAssistantEnabled = try container.decodeIfPresent(Bool.self, forKey: .isCloudAssistantEnabled) ?? fallback.isCloudAssistantEnabled
        isCloudCheckInEnabled = try container.decodeIfPresent(Bool.self, forKey: .isCloudCheckInEnabled) ?? fallback.isCloudCheckInEnabled
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
