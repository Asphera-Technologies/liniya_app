//
//  TaskDay.swift
//  Linea
//
//  «Когда» у задачи так, как его говорят: сегодня, завтра, на неделе, в
//  пятницу, когда-нибудь. В самой задаче это превращается в два знакомых поля:
//  день (`LineaTask.date`) и срок (`LineaTask.deadline`).
//
//  «На неделе» — не день, а срок: задача без дня, которую нужно закрыть до
//  конца недели; в какой день за неё взяться, решает план.
//

import Foundation

nonisolated enum TaskDay: Hashable, Sendable {
    case today
    case tomorrow
    /// «На неделе»: без дня, к концу недели.
    case thisWeek
    /// Конкретный день — начало дня в календаре пользователя.
    case date(Date)
    /// «Когда-нибудь», «без даты»: ни дня, ни срока.
    case someday

    /// День и срок, которые получит задача.
    func resolve(time: TimeContext, profile: UserProfile) -> (date: Date?, deadline: Date?) {
        switch self {
        case .today: return (time.today, nil)
        case .tomorrow: return (time.adding(days: 1, to: time.today), nil)
        case .thisWeek: return (nil, TaskDay.endOfWeek(time: time, profile: profile))
        case .date(let day): return (time.startOfDay(day), nil)
        case .someday: return (nil, nil)
        }
    }

    /// Конец недели для «на неделе»: воскресенье этой недели в конце рабочего
    /// дня. В субботу и воскресенье «на неделе» значит «на будущей неделе».
    static func endOfWeek(time: TimeContext, profile: UserProfile) -> Date {
        let today = time.today
        let weekday = time.calendar.component(.weekday, from: today)
        // Календарь: 1 — воскресенье, 2 — понедельник, … 7 — суббота.
        var offset = (8 - weekday) % 7
        if weekday == 7 || weekday == 1 { offset += 7 }
        return time.date(on: time.adding(days: offset, to: today), at: profile.workdayEnd)
    }

    /// Сколько дней прошло с понедельника этой недели: понедельник — 0,
    /// воскресенье — 6. Не зависит от того, с какого дня неделя начинается
    /// в настройках телефона.
    static func daysSinceMonday(_ day: Date, time: TimeContext) -> Int {
        (time.calendar.component(.weekday, from: day) + 5) % 7
    }

    /// Понедельник следующей недели.
    static func nextMonday(time: TimeContext) -> Date {
        time.adding(days: 7 - daysSinceMonday(time.today, time: time), to: time.today)
    }
}
