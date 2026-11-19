import Foundation

nonisolated enum VoiceTaskWindow {
    static func find(
        minutes: Int, day: Date, deadline: Date?, context: RescheduleContext, plan: DayPlan?
    ) -> DateInterval? {
        guard minutes > 0 else { return nil }
        let time = context.time
        var occupied = context.commitments(on: day)
        let blocks = plan.flatMap { time.isSameDay($0.day, day) ? $0.blocks : nil } ?? []
        occupied += blocks.filter { $0.kind != .rest }.map {
            Commitment(id: $0.id, title: $0.title, start: $0.start, end: $0.end,
                       kind: .task, source: .tasks, taskID: $0.taskID)
        }
        let represented = Set(occupied.compactMap(\.taskID))
        let unscheduled = context.tasks.filter {
            $0.isOpen && !$0.isFixed && !represented.contains($0.id)
                && ($0.date.map { time.isSameDay($0, day) } ?? false)
        }.reduce(0) { $0 + PlanDuration.minutes(for: $1, calibration: context.calibration) }
        let earliest = Date(timeIntervalSinceReferenceDate: (time.now.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60)
        let windows = FreeWindows.compute(day: day, now: earliest, profile: context.profile,
                                          commitments: occupied, config: context.config, time: time)
        guard windows.reduce(0, { $0 + $1.duration }) >= TimeInterval((minutes + unscheduled) * 60) else { return nil }
        guard let slot = WindowFinder.nextFit(minutes: minutes, on: day, notBefore: earliest,
                                              profile: context.profile, commitments: occupied,
                                              config: context.config, time: time),
              deadline.map({ slot.end <= $0 }) ?? true else { return nil }
        return slot
    }

    static func isEventCommand(_ text: String) -> Bool {
        let words = text.lowercased().split { !$0.isLetter }
        let commands: Set<Substring> = ["запиши", "записать", "занеси", "внеси", "добавь", "создай"]
        guard let index = words.firstIndex(where: { commands.contains($0) }), index <= 2,
              let object = words.dropFirst(index + 1).first(where: { $0 != "мне" }) else { return false }
        if object == "событие" { return true }
        if object == "задачу" || object == "задачку" { return false }
        return ["запиши", "записать", "занеси", "внеси"].contains(words[index])
    }
}
