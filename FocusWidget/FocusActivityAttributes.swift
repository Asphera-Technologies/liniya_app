import ActivityKit
import AppIntents
import Foundation

nonisolated struct FocusActivityAttributes: ActivityAttributes {
    let taskID: String
    let startedAt: Date

    struct ContentState: Codable, Hashable {
        let title: String
        let countdownStart: Date
        let endsAt: Date
        let pausedSeconds: Int?
        let nextEvent: String?
        let nextEventStart: Date?
    }
}

nonisolated enum FocusActivityAction: String {
    case pause, resume, finish
}

struct FocusActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Управлять таймером"
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Задача") var taskID: String
    @Parameter(title: "Сеанс") var startedAt: String
    @Parameter(title: "Действие") var action: String

    init() {}

    init(_ action: FocusActivityAction, for attributes: FocusActivityAttributes) {
        self.action = action.rawValue
        taskID = attributes.taskID
        // The app matches the exact start time to reject actions from an old session.
        startedAt = String(attributes.startedAt.timeIntervalSinceReferenceDate.bitPattern)
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !FOCUS_WIDGET
        if let id = UUID(uuidString: taskID), let session = UInt64(startedAt),
           let action = FocusActivityAction(rawValue: action) {
            await FocusActivityController.handle?(action, id, Date(timeIntervalSinceReferenceDate: Double(bitPattern: session)))
        }
        #endif
        return .result()
    }
}
