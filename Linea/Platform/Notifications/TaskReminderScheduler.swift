import Foundation
import OSLog
import UserNotifications

@MainActor
final class TaskReminderScheduler {
    private let center = UNUserNotificationCenter.current()
    private let prefix = "linea.task-reminder."

    enum Result {
        case ready, denied, tooLate, failed
    }

    func enable() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default: return false
        }
    }

    func sync(_ task: LineaTask, time: TimeContext) async -> Result {
        let id = prefix + task.id.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
        guard task.isOpen, let start = task.scheduledStart, let lead = task.reminderLeadMinutes else { return .ready }
        let remindAt = start.addingTimeInterval(-TimeInterval(lead * 60))
        guard remindAt > time.now else { return .tooLate }
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return .denied }
        var date = time.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: remindAt)
        date.timeZone = time.calendar.timeZone
        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = lead > 0 ? "Начало через \(lead) мин." : "Пора начинать."
        content.sound = .default
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: false)))
            return .ready
        } catch {
            LineaLog.plan.error("Не удалось поставить напоминание: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }
}
