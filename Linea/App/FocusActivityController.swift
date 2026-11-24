import ActivityKit
import OSLog
import UIKit

@MainActor
enum FocusActivityController {
    static var handle: (@MainActor (FocusActivityAction, UUID, Date) async -> Void)?

    static func sync(focus: TaskFocus?, nextEvent: Commitment?, now: Date) async {
        func matches(_ activity: Activity<FocusActivityAttributes>) -> Bool {
            activity.attributes.taskID == focus?.taskID.uuidString && activity.attributes.startedAt == focus?.startedAt
        }
        for activity in Activity<FocusActivityAttributes>.activities where !matches(activity) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard let focus, !LineaApp.isUITesting else { return }
        let state = FocusActivityAttributes.ContentState(
            title: focus.title,
            countdownStart: focus.timer.endsAt.addingTimeInterval(-TimeInterval(focus.minutes) * 60),
            endsAt: focus.timer.endsAt,
            pausedSeconds: focus.isPaused ? focus.remainingSeconds(at: now) : nil,
            nextEvent: nextEvent?.title,
            nextEventStart: nextEvent?.start
        )
        let content = ActivityContent(state: state, staleDate: focus.isPaused ? nil : focus.timer.endsAt)
        if let activity = Activity<FocusActivityAttributes>.activities.first(where: matches) {
            if activity.content.state != state || activity.content.staleDate != content.staleDate {
                await activity.update(content)
            }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled, UIApplication.shared.applicationState == .active {
            let attributes = FocusActivityAttributes(taskID: focus.taskID.uuidString, startedAt: focus.startedAt)
            do {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
            } catch {
                LineaLog.plan.error("Не удалось показать таймер в Live Activity: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
