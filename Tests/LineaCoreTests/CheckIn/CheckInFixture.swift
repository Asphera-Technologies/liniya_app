//
//  CheckInFixture.swift
//  LineaCoreTests
//
//  Вечер wow-дня как рассказ: что человек говорит в итоге дня про задачи из
//  `WowFixture`. Один текст — и для правил, и для сквозного сценария.
//

import Foundation
@testable import LineaCore

nonisolated enum CheckInFixture {
    /// Около минуты речи — типичный итог дня.
    static let transcript = """
    Сегодня сделал презентацию КП и ответил на письма. Созвон с командой провели, но затянулся. \
    Тренировку пропустил, не было сил. Разработку Linea начал, но не закончил. \
    Ещё созвонился с поставщиком минут на сорок. Работал часов семь. День тяжёлый, очень устал. \
    Запомни, что после обеда я плохо соображаю.
    """

    static func request(
        _ transcript: String = transcript,
        tasks: [LineaTask] = WowFixture.tasks,
        facts: [String] = [],
        time: TimeContext = WowFixture.evening
    ) -> CheckInRequest {
        CheckInRequest(
            transcript: transcript,
            day: WowFixture.today,
            tasks: CheckInRequest.relevantTasks(from: tasks, day: WowFixture.today, time: time),
            knownFacts: facts,
            time: time
        )
    }

    static func parse(_ transcript: String, tasks: [LineaTask] = WowFixture.tasks) -> CheckInExtraction {
        RuleBasedCheckInExtractor().parse(request(transcript, tasks: tasks))
    }

    static func status(of taskID: UUID, in extraction: CheckInExtraction) -> TaskOutcomeStatus? {
        extraction.outcome(for: taskID)?.status
    }
}
