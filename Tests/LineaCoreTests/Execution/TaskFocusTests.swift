import Testing
import Foundation
@testable import LineaCore

/// Минимальный фокус после «Начать»: название, сколько отведено, с какого
/// времени, «Завершить» и «Не получается продолжить». Среда 9 сентября 2026,
/// Москва.
@Suite("Фокус после «Начать»")
struct TaskFocusTests {
    private let execution = TaskExecutionUseCase()
    private let lifecycle = TaskLifecycle()

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "F0C00000-0000-0000-0000-%012d", n))!
    }

    private var presentation: LineaTask {
        LineaTask(id: id(1), title: "Подготовить презентацию", date: WowFixture.today, priority: .important,
                  createdAt: WowFixture.created, estimatedMinutes: 45, cognitiveDemand: .deep)
    }

    private func record(_ tasks: [LineaTask], at time: TimeContext) -> DayRecord {
        DayRecord(day: WowFixture.today, snapshot: PlanFixture.snapshot(tasks: tasks, commitments: [], goals: [], at: time),
                  state: PlanFixture.state(energy: 0.6, confidence: 0.9, advice: .normal, at: time), updatedAt: time.now)
    }

    @Test("Экран заказчика: «Подготовить презентацию», «~45 мин», «Начато в 11:20»")
    func customerExample() throws {
        let time = WowFixture.time(11, 20)
        let output = try #require(execution.run(.start, task: presentation, record: record([presentation], at: time),
                                                plannedMinutes: 45, at: time.now))
        let focus = try #require(TaskFocus.of(output.task, record: output.record, calibration: .default,
                                              time: WowFixture.time(11, 32)))
        #expect(focus.title == "Подготовить презентацию")
        #expect(focus.duration == "~45 мин")
        #expect(focus.started == "Начато в 11:20")
        #expect(focus.startedAt == WowFixture.moment(11, 20))
        #expect(TaskFocus.hint == "Можно выйти из приложения — выполнение продолжается.")
        #expect(TaskFocus.stopTitle == "Не получается продолжить")
    }

    @Test("Сколько отведено — то, что Linea отвела при «Начать», а не оценка задачи")
    func allottedMinutes() throws {
        let time = WowFixture.time(10)
        let output = try #require(execution.run(.start, task: presentation, record: record([presentation], at: time),
                                                plannedMinutes: 20, at: time.now))
        #expect(TaskFocus.of(output.task, record: output.record, calibration: .default, time: time)?.duration == "~20 мин",
                "До встречи было 20 минут — столько и отвели")

        // Начали из списка или карточки вчерашним днём — записи в сегодняшнем
        // дне нет: обычная длительность задачи с калибровкой.
        let started = try #require(lifecycle.start(presentation, suggestionID: nil, at: WowFixture.moment(17, 5, dayOffset: -1)))
        let focus = try #require(TaskFocus.of(started, record: record([started], at: time), calibration: .default, time: time))
        #expect(focus.duration == "~45 мин")
        #expect(focus.started == "Начато вчера в 17:05")
        var older = started
        older.startedAt = WowFixture.moment(9, 0, dayOffset: -3)
        #expect(TaskFocus.of(older, record: nil, calibration: .default, time: time)?.started == "Начато в вс, 6 сен")
    }

    @Test("Фокуса нет у не начатой, сделанной и отменённой задачи")
    func onlyStarted() throws {
        let time = WowFixture.time(10)
        #expect(TaskFocus.of(presentation, record: nil, calibration: .default, time: time) == nil)
        let started = try #require(lifecycle.start(presentation, suggestionID: nil, at: time.now))
        let finished = try #require(lifecycle.finish(started, suggestionID: nil, at: WowFixture.moment(10, 40)))
        #expect(TaskFocus.of(finished, record: nil, calibration: .default, time: WowFixture.time(10, 40)) == nil)
        var cancelled = started
        cancelled.cancelledAt = WowFixture.moment(10, 5)
        #expect(TaskFocus.of(cancelled, record: nil, calibration: .default, time: time) == nil)
        let released = try #require(lifecycle.notNow(started, at: WowFixture.moment(10, 10)))
        #expect(TaskFocus.of(released, record: nil, calibration: .default, time: WowFixture.time(10, 10)) == nil,
                "«Не получается продолжить» — задача больше не в работе")
    }

    @Test("После запуска приложения — фокус последней начатой задачи, если её начали не больше 12 часов назад")
    func resumable() throws {
        let time = WowFixture.time(14)
        var morning = presentation
        morning.startedAt = WowFixture.moment(9)
        var lunch = LineaTask(id: id(2), title: "Ответить клиенту", date: WowFixture.today, createdAt: WowFixture.created)
        lunch.startedAt = WowFixture.moment(13, 30)
        var done = LineaTask(id: id(3), title: "Отчёт", date: WowFixture.today, createdAt: WowFixture.created)
        done.startedAt = WowFixture.moment(13, 50)
        done.isDone = true
        #expect(TaskFocus.resumable(in: [morning, lunch, done], time: time)?.id == lunch.id, "Последняя начатая и открытая")
        #expect(TaskFocus.resumable(in: [morning], time: WowFixture.time(21, 1)) == nil, "Больше 12 часов — забыли «Завершить»")
        #expect(TaskFocus.resumable(in: [presentation], time: time) == nil)
    }

    @Test("«Завершить» в фокусе: задача сделана, сколько заняло — в ответе над «Сейчас»")
    func finishNote() throws {
        let started = try #require(lifecycle.start(presentation, suggestionID: nil, at: WowFixture.moment(11, 20)))
        let finished = try #require(lifecycle.finish(started, suggestionID: nil, at: WowFixture.moment(11, 55)))
        #expect(TaskExecutionText.finished(finished) == "Сделано за 35 мин.")
        var long = finished
        long.actualMinutes = 70
        #expect(TaskExecutionText.finished(long) == "Сделано за 1 ч 10 мин.")
        let direct = try #require(lifecycle.finish(presentation, suggestionID: nil, at: WowFixture.moment(12)))
        #expect(TaskExecutionText.finished(direct) == "Сделано.", "Не начинали — сколько заняло, неизвестно")
        #expect(TaskExecutionText.declined == "Хорошо, подберу другое.")
    }

    @Test("«Не получается продолжить»: начатая отпущена, в дне — сколько успел поработать")
    func cannotContinue() throws {
        let time = WowFixture.time(11, 20)
        let started = try #require(execution.run(.start, task: presentation, record: record([presentation], at: time),
                                                 plannedMinutes: 45, at: time.now))
        let stopped = try #require(execution.run(.notNow, task: started.task, record: started.record,
                                                 plannedMinutes: 45, at: WowFixture.moment(11, 42)))
        #expect(stopped.task.startedAt == nil)
        #expect(stopped.task.status(at: WowFixture.moment(11, 42)) == .deferred)
        #expect(stopped.record?.feedback.last?.kind == .taskNotNow(taskID: presentation.id, wasStarted: true, workedMinutes: 22))

        let notStarted = try #require(execution.run(.notNow, task: presentation, record: record([presentation], at: time),
                                                    plannedMinutes: 45, at: time.now))
        #expect(notStarted.record?.feedback.last?.kind == .taskNotNow(taskID: presentation.id, wasStarted: false))
    }

    @Test("Отклик «Не сейчас», записанный до фокуса, читается: сколько успел — неизвестно")
    func oldNotNowFeedback() throws {
        let json = """
        {"id":"\(id(9).uuidString)","at":800000000,"kind":{"taskNotNow":{"taskID":"\(id(1).uuidString)","wasStarted":true}}}
        """
        let feedback = try JSONDecoder().decode(UserFeedback.self, from: Data(json.utf8))
        #expect(feedback.kind == .taskNotNow(taskID: id(1), wasStarted: true, workedMinutes: nil))
        let roundTrip = try JSONDecoder().decode(UserFeedback.self, from: JSONEncoder().encode(feedback))
        #expect(roundTrip.kind == feedback.kind)
    }
}
