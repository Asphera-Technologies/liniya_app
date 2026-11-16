import Foundation

nonisolated struct TaskTimer: Codable, Hashable, Sendable {
    let minutes: Int
    private(set) var endsAt: Date
    private(set) var pausedAt: Date?
    private(set) var pausedSeconds: TimeInterval = 0

    init(minutes: Int, startedAt: Date) {
        self.minutes = max(1, minutes)
        endsAt = startedAt.addingTimeInterval(TimeInterval(self.minutes) * 60)
    }

    func remainingSeconds(at time: Date) -> Int {
        max(0, Int(endsAt.timeIntervalSince(pausedAt ?? time).rounded(.up)))
    }

    func workedUntil(_ time: Date) -> Date {
        (pausedAt ?? time).addingTimeInterval(-pausedSeconds)
    }

    mutating func setPaused(_ paused: Bool, at time: Date) {
        if paused {
            if pausedAt == nil { pausedAt = time }
        } else if let pausedAt {
            let interval = max(0, time.timeIntervalSince(pausedAt))
            pausedSeconds += interval
            endsAt = endsAt.addingTimeInterval(interval)
            self.pausedAt = nil
        }
    }
}
