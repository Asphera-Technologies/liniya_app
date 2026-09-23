//
//  NudgeScheduler.swift
//  Linea
//
//  Turns the core's `Nudge`s into local notifications with action buttons.
//  Scheduled when a plan is accepted, re-synced on every foreground and after
//  every task change, cancelled when a task is done. iOS runs no code «at
//  14:30»; the text is computed in advance from the accepted plan.
//

import Foundation
import UserNotifications

@MainActor
final class NudgeScheduler {

    enum Category {
        static let behind = "LINEA_BEHIND"
        static let review = "LINEA_REVIEW"
    }

    enum ActionID {
        static let finishNow = "FINISH_NOW"
        static let deferTask = "DEFER"
        static let rateGreat = "RATE_GREAT"
        static let rateOK = "RATE_OK"
        static let rateHard = "RATE_HARD"
        static let tellDay = "TELL_DAY"
    }

    enum UserInfoKey {
        static let nudgeID = "nudgeID"
        static let taskID = "taskID"
        static let kind = "kind"
    }

    private static let identifierPrefix = "linea."

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// Registers the action categories once (idempotent).
    func registerCategories() {
        let behind = UNNotificationCategory(
            identifier: Category.behind,
            actions: [
                UNNotificationAction(identifier: ActionID.finishNow, title: "Закрываем сейчас", options: [.foreground]),
                UNNotificationAction(identifier: ActionID.deferTask, title: "Переносим", options: []),
            ],
            intentIdentifiers: [],
            options: []
        )
        let review = UNNotificationCategory(
            identifier: Category.review,
            actions: [
                // Главный ответ — рассказать итог дня; три оценки — если некогда.
                UNNotificationAction(identifier: ActionID.tellDay, title: "Рассказать", options: [.foreground]),
                UNNotificationAction(identifier: ActionID.rateGreat, title: "Отлично", options: []),
                UNNotificationAction(identifier: ActionID.rateOK, title: "Нормально", options: []),
                UNNotificationAction(identifier: ActionID.rateHard, title: "Тяжело", options: []),
            ],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([behind, review])
    }

    /// Asks for permission the first time; returns whether notifications are allowed.
    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    /// Replaces all pending Linea notifications with the given nudges.
    /// Only nudges in the future are scheduled; due ones are shown in-app.
    func sync(_ nudges: [Nudge], time: TimeContext) async {
        await cancelAll()
        for nudge in nudges where nudge.fireAt > time.now {
            let content = UNMutableNotificationContent()
            content.title = nudge.title
            content.body = nudge.body
            content.sound = .default
            content.interruptionLevel = .active
            content.categoryIdentifier = nudge.kind == .eveningCheckIn ? Category.review : Category.behind
            var userInfo: [String: String] = [UserInfoKey.nudgeID: nudge.id, UserInfoKey.kind: nudge.kind.rawValue]
            if let taskID = nudge.taskID { userInfo[UserInfoKey.taskID] = taskID.uuidString }
            content.userInfo = userInfo

            let components = time.calendar.dateComponents(
                in: time.timeZone,
                from: nudge.fireAt
            )
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(
                    timeZone: time.timeZone,
                    year: components.year, month: components.month, day: components.day,
                    hour: components.hour, minute: components.minute
                ),
                repeats: false
            )
            let request = UNNotificationRequest(identifier: Self.identifier(for: nudge), content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// Removes pending notifications bound to a task (e.g. the task was completed).
    func cancel(taskID: UUID) async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .filter { ($0.content.userInfo[UserInfoKey.taskID] as? String) == taskID.uuidString }
            .map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func identifier(for nudge: Nudge) -> String {
        identifierPrefix + nudge.id
    }

    /// Maps a delivered notification response back to a core action.
    static func response(actionIdentifier: String, userInfo: [AnyHashable: Any]) -> NotificationResponse? {
        let nudgeID = userInfo[UserInfoKey.nudgeID] as? String
        let taskID = (userInfo[UserInfoKey.taskID] as? String).flatMap(UUID.init(uuidString:))
        switch actionIdentifier {
        case ActionID.finishNow:
            guard let taskID, let nudgeID else { return nil }
            return .finishNow(nudgeID: nudgeID, taskID: taskID)
        case ActionID.deferTask:
            guard let taskID, let nudgeID else { return nil }
            return .deferTask(nudgeID: nudgeID, taskID: taskID)
        case ActionID.rateGreat: return .rate(.great)
        case ActionID.rateOK: return .rate(.ok)
        case ActionID.rateHard: return .rate(.hard)
        case ActionID.tellDay: return .tellDay
        default:
            // Нажатие на само вечернее напоминание — тоже «рассказать».
            if (userInfo[UserInfoKey.kind] as? String) == NudgeKind.eveningCheckIn.rawValue { return .tellDay }
            return nudgeID.map { .open(nudgeID: $0) }
        }
    }

    enum NotificationResponse: Equatable {
        case finishNow(nudgeID: String, taskID: UUID)
        case deferTask(nudgeID: String, taskID: UUID)
        case rate(DayRating)
        case open(nudgeID: String)
        /// Открыть «Итог дня».
        case tellDay
    }
}
