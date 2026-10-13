//
//  WindowFinder.swift
//  Linea
//
//  Где задача поместится целиком: первое свободное окно дня — внутри рабочего
//  дня, вне встреч, еды и задач со своим временем — не раньше заданного
//  момента и не короче, чем нужно задаче. Нужен, когда Linea сама ищет время:
//  «Нет времени» в ответ на «Почему не сейчас?», «Позже сегодня» и «Пусть
//  Linea решит» в «Перенести».
//

import Foundation

nonisolated enum WindowFinder {
    /// Первые `minutes` свободного времени подряд в дне `day`, не раньше
    /// `earliest`; nil — в этот день задача целиком не помещается.
    static func nextFit(
        minutes: Int,
        on day: Date,
        notBefore earliest: Date,
        profile: UserProfile,
        commitments: [Commitment],
        config: EngineConfig = .default,
        time: TimeContext
    ) -> DateInterval? {
        let needed = TimeInterval(max(1, minutes) * 60)
        return FreeWindows.compute(day: day, now: earliest, profile: profile, commitments: commitments,
                                   config: config, time: time)
            .first { $0.duration >= needed }
            .map { DateInterval(start: $0.start, duration: needed) }
    }
}
