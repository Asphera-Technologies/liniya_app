//
//  FreeWindows.swift
//  Linea
//
//  «Сколько времени у меня реально есть сегодня» — the workday minus everything
//  already committed. Kept separate from the planner because rules also need
//  the windows (a nutrition rule wants to know where a meal fits), and because
//  subtracting intervals is the one place off-by-one errors love to live.
//

import Foundation

nonisolated enum FreeWindows {
    /// Free intervals of `day` after `now`, inside the profile's workday and
    /// outside every commitment. Windows shorter than `minimumBlockMinutes`
    /// are dropped: a 7-minute gap is not a place to put work.
    static func compute(
        day: Date,
        now: Date,
        profile: UserProfile,
        commitments: [Commitment],
        config: EngineConfig = .default,
        time: TimeContext
    ) -> [DateInterval] {
        let dayStart = time.startOfDay(day)
        let workdayStart = time.date(on: dayStart, at: profile.workdayStart)
        let workdayEnd = time.date(on: dayStart, at: profile.workdayEnd)
        let start = max(now, workdayStart)
        guard start < workdayEnd else { return [] }

        let bounds = DateInterval(start: start, end: workdayEnd)
        let busy = StateMath.union(commitments.compactMap { clip($0.interval, to: bounds) })

        var free: [DateInterval] = []
        var cursor = bounds.start
        for interval in busy {
            if interval.start > cursor {
                free.append(DateInterval(start: cursor, end: interval.start))
            }
            cursor = max(cursor, interval.end)
        }
        if cursor < bounds.end {
            free.append(DateInterval(start: cursor, end: bounds.end))
        }

        let minimum = TimeInterval(config.minimumBlockMinutes * 60)
        return free.filter { $0.duration >= minimum }
    }

    /// The part of `interval` that lies inside `bounds`, or nil if they miss.
    static func clip(_ interval: DateInterval, to bounds: DateInterval) -> DateInterval? {
        let start = max(interval.start, bounds.start)
        let end = min(interval.end, bounds.end)
        guard end > start else { return nil }
        return DateInterval(start: start, end: end)
    }
}
