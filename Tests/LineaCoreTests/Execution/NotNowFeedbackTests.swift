import Testing
import Foundation
@testable import LineaCore

/// «Не сейчас» — обратная связь: Linea убирает предложение, подбирает другое
/// и иногда спрашивает, почему. Каждый ответ меняет план. Среда 9 сентября
/// 2026, Москва, рабочий день 9–21.
@Suite("«Не сейчас»: почему и что дальше")
struct NotNowFeedbackTests {
    private let feedback = NotNowFeedback()
    private let execution = TaskExecutionUseCase()
    private let nextAction = NextActionUseCase(renderer: RuleBasedExplainer())

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "90000000-0000-0000-0000-%012d", n))!
    }

    /// Важная презентация на 45 минут, обычное письмо и лёгкий быт.
    private var tasks: [LineaTask] {
        [
            LineaTask(id: id(1), title: "Подготовить презентацию", date: WowFixture.today, priority: .important,
                      createdAt: WowFixture.created, estimatedMinutes: 45, cognitiveDemand: .deep),
            LineaTask(id: id(2), title: "Разобрать письмо", date: WowFixture.today,
                      createdAt: WowFixture.created.addingTimeInterval(60), estimatedMinutes: 15, cognitiveDemand: .light),
            LineaTask(id: id(3), title: "Оплатить интернет", date: WowFixture.today,
                      createdAt: WowFixture.created.addingTimeInterval(120), estimatedMinutes: 10, cognitiveDemand: .light),
        ]
    }

    private func record(_ tasks: [LineaTask], commitments: [Commitment] = [], energy: Double = 0.7,
                        at time: TimeContext) -> DayRecord {
        DayRecord(day: WowFixture.today,
                  snapshot: PlanFixture.snapshot(tasks: tasks, commitments: commitments, goals: [], at: time),
                  state: PlanFixture.state(energy: energy, confidence: 0.9, advice: .normal, at: time), updatedAt: time.now)
    }

    private func meeting(_ hour: Int, _ minute: Int = 0, until endHour: Int, _ endMinute: Int = 0) -> Commitment {
        Commitment(id: "meeting-\(hour)-\(minute)", title: "Встреча с клиентом", start: WowFixture.moment(hour, minute),
                   end: WowFixture.moment(endHour, endMinute), kind: .meeting, source: .calendar)
    }

    // MARK: Когда спрашивать

    @Test("Тон и вопрос заказчика: «Хорошо, подберу другое.», «Почему не сейчас?» и четыре ответа")
    func customerWording() throws {
        let time = WowFixture.time(10)
        let question = try #require(feedback.question(for: tasks[0], record: record(tasks, at: time), tasks: tasks,
                                                      calibration: .default, time: time))
        #expect(TaskExecutionText.declined == "Хорошо, подберу другое.")
        #expect(question.title == "Почему не сейчас?")
        #expect(question.reasons.map(\.title) == ["Нет времени", "Нет сил", "Не хочется", "Неактуально"])
        #expect(!question.wasStarted)
    }

    @Test("Не спрашивает про обычное дело: ответ ничего не поменяет")
    func ordinaryTaskIsNotAsked() {
        let time = WowFixture.time(10)
        #expect(feedback.question(for: tasks[1], record: record(tasks, at: time), tasks: tasks,
                                  calibration: .default, time: time) == nil)
        var deferred = tasks[1]
        deferred.deferralCount = 1
        #expect(feedback.question(for: deferred, record: record([deferred], at: time), tasks: [deferred],
                                  calibration: .default, time: time) != nil, "Её уже переносили — спросить стоит")
        var soon = tasks[1]
        soon.deadline = WowFixture.moment(18, 0, dayOffset: 1)
        #expect(feedback.question(for: soon, record: record([soon], at: time), tasks: [soon],
                                  calibration: .default, time: time) != nil, "Срок завтра — спросить стоит")
    }

    @Test("Не спрашивает, когда причина видна по данным: окна не хватает или сил мало")
    func obviousCauseIsNotAsked() {
        let time = WowFixture.time(10)
        // До встречи 20 минут, а презентации нужно 45.
        let busy = record(tasks, commitments: [meeting(10, 20, until: 11)], at: time)
        #expect(feedback.question(for: tasks[0], record: busy, tasks: tasks, calibration: .default, time: time) == nil)
        // Сил мало, а задача сложная.
        let tired = record(tasks, energy: 0.05, at: WowFixture.time(15))
        #expect(feedback.question(for: tasks[0], record: tired, tasks: tasks, calibration: .default,
                                  time: WowFixture.time(15)) == nil)
    }

    @Test("Не часто: раз в два часа, про задачу — раз в день, три в день, два без ответа — до завтра")
    func notTooOften() throws {
        var important = tasks
        important[1].priority = .important
        important[2].priority = .important
        var day = record(important, at: WowFixture.time(10))
        let first = try #require(feedback.question(for: important[0], record: day, tasks: important,
                                                   calibration: .default, time: WowFixture.time(10)))
        day = feedback.asking(first, in: day, at: WowFixture.moment(10))
        #expect(feedback.question(for: important[1], record: day, tasks: important, calibration: .default,
                                  time: WowFixture.time(11, 30)) == nil, "Меньше двух часов после прошлого")
        #expect(feedback.question(for: important[0], record: day, tasks: important, calibration: .default,
                                  time: WowFixture.time(13)) == nil, "Про ту же задачу — раз в день")
        let second = try #require(feedback.question(for: important[1], record: day, tasks: important,
                                                    calibration: .default, time: WowFixture.time(12, 1)))
        day = feedback.asking(second, in: day, at: WowFixture.moment(12, 1))
        #expect(feedback.question(for: important[2], record: day, tasks: important, calibration: .default,
                                  time: WowFixture.time(14, 30)) == nil, "Два вопроса без ответа — до завтра")

        // Ответил на второй — можно спросить третий раз, но не четвёртый.
        let answered = feedback.answer(.unwilling, to: second, task: important[1], record: day,
                                       calibration: .default, time: WowFixture.time(12, 2))
        day = try #require(answered.record)
        let third = try #require(feedback.question(for: important[2], record: day, tasks: important,
                                                   calibration: .default, time: WowFixture.time(14, 30)))
        day = feedback.asking(third, in: day, at: WowFixture.moment(14, 30))
        var fourth = LineaTask(id: id(4), title: "Отчёт", date: WowFixture.today, priority: .important,
                               createdAt: WowFixture.created, estimatedMinutes: 30)
        fourth.deferralCount = 2
        #expect(feedback.question(for: fourth, record: day, tasks: important + [fourth], calibration: .default,
                                  time: WowFixture.time(17)) == nil, "Не больше трёх вопросов в день")
    }

    @Test("Начатую отпустили — «Что помешало?»; от задачи уже отказывались сегодня — спросить стоит")
    func startedAndDeclinedBefore() throws {
        let time = WowFixture.time(10)
        var started = tasks[1]
        started.startedAt = WowFixture.moment(9, 40)
        let question = try #require(feedback.question(for: started, record: record([started], at: time), tasks: [started],
                                                      calibration: .default, time: time))
        #expect(question.title == "Что помешало?")
        #expect(question.wasStarted)

        let declined = try #require(execution.run(.notNow, task: tasks[2], record: record(tasks, at: time),
                                                  plannedMinutes: 10, at: time.now))
        var again = declined.task
        again.deferredUntil = nil
        #expect(feedback.question(for: again, record: declined.record, tasks: tasks, calibration: .default,
                                  time: WowFixture.time(11, 40)) != nil, "Второй отказ за день — спросить стоит")
    }

    // MARK: Что меняет ответ

    @Test("«Нет времени»: не раньше чем через два часа — в первое окно, где задача помещается целиком")
    func noTime() throws {
        let time = WowFixture.time(10)
        // Встреча 12:00–13:30: окно с 12:00 занято — Linea вернётся в 13:30.
        let day = record(tasks, commitments: [meeting(12, until: 13, 30)], at: time)
        let question = try #require(feedback.question(for: tasks[0], record: day, tasks: tasks, calibration: .default, time: time))
        let declined = try #require(execution.run(.notNow, task: tasks[0], record: day, plannedMinutes: 45, at: time.now))
        let outcome = feedback.answer(.noTime, to: question, task: declined.task, record: declined.record,
                                      calibration: .default, time: time)
        #expect(outcome.task.deferredUntil == WowFixture.moment(13, 30))
        #expect(outcome.reply == "Хорошо, вернусь к ней в 13:30.")
        #expect(!outcome.canUndo)
        #expect(outcome.record?.feedback.last?.kind == .notNowReason(NotNowAnswer(taskID: tasks[0].id, reason: .noTime)))

        // Вечером окна на сегодня нет — завтра с начала рабочего дня.
        let evening = WowFixture.time(19, 30)
        let late = feedback.answer(.noTime, to: question, task: tasks[0], record: record(tasks, at: evening),
                                   calibration: .default, time: evening)
        #expect(late.task.deferredUntil == WowFixture.moment(9, 0, dayOffset: 1))
        #expect(late.reply == "Хорошо, вернусь к ней завтра.")
    }

    @Test("«Нет сил»: два часа «Сейчас» предлагает полегче — с понятной причиной")
    func noEnergy() throws {
        let time = WowFixture.time(10)
        var current = tasks
        // Без ответа сначала — важная презентация.
        let first = try #require(nextAction.run(record: record(current, at: time), tasks: current, calibration: .default, time: time))
        #expect(first.taskID == current[0].id)

        // Отказался от письма — но про сложное это не говорит; ответ «Нет сил».
        let question = NotNowQuestion(taskID: current[1].id, title: "Почему не сейчас?", wasStarted: false, suggestionID: nil)
        let declined = try #require(execution.run(.notNow, task: current[1], record: record(current, at: time),
                                                  plannedMinutes: 15, at: time.now))
        current[1] = declined.task
        let outcome = feedback.answer(.noEnergy, to: question, task: declined.task, record: declined.record,
                                      calibration: .default, time: time)
        #expect(outcome.reply == "Хорошо, пока предложу что-то полегче.")
        #expect(outcome.task.deferredUntil == declined.task.deferredUntil, "Сама задача — как без ответа")
        let day = try #require(outcome.record)

        let lighter = try #require(nextAction.run(record: day, tasks: current, calibration: .default, time: WowFixture.time(10, 1)))
        #expect(lighter.taskID == current[2].id, "Сложное подождёт — сейчас лёгкое")
        #expect(lighter.reason == "Это полегче — пока сил немного.")
        let later = try #require(nextAction.run(record: day, tasks: current, calibration: .default, time: WowFixture.time(12, 1)))
        #expect(later.taskID == current[0].id, "Два часа прошли — снова важное")
    }

    @Test("«Не хочется»: как без ответа, полтора часа; ответ записан")
    func unwilling() throws {
        let time = WowFixture.time(10)
        let question = try #require(feedback.question(for: tasks[0], record: record(tasks, at: time), tasks: tasks,
                                                      calibration: .default, time: time))
        let declined = try #require(execution.run(.notNow, task: tasks[0], record: record(tasks, at: time),
                                                  plannedMinutes: 45, at: time.now))
        let outcome = feedback.answer(.unwilling, to: question, task: declined.task, record: declined.record,
                                      calibration: .default, time: time)
        #expect(outcome.task == declined.task)
        #expect(outcome.reply == "Хорошо, вернусь к ней позже.")
        #expect(outcome.record?.notNowAnswers.map(\.answer.reason) == [.unwilling])
    }

    @Test("«Неактуально»: задача уходит из планов, «Вернуть» возвращает её как была")
    func irrelevantAndUndo() throws {
        let time = WowFixture.time(10)
        let question = try #require(feedback.question(for: tasks[0], record: record(tasks, at: time), tasks: tasks,
                                                      calibration: .default, time: time))
        let declined = try #require(execution.run(.notNow, task: tasks[0], record: record(tasks, at: time),
                                                  plannedMinutes: 45, at: time.now))
        let outcome = feedback.answer(.irrelevant, to: question, task: declined.task, record: declined.record,
                                      calibration: .default, time: time)
        #expect(outcome.task.status(at: time.now) == .cancelled)
        #expect(outcome.reply == "Убрала из планов.")
        #expect(outcome.canUndo)
        #expect(outcome.record?.feedback.suffix(2).map(\.kind) == [
            .notNowReason(NotNowAnswer(taskID: tasks[0].id, reason: .irrelevant)),
            .taskCancelled(taskID: tasks[0].id),
        ])

        let undone = try #require(feedback.undo(outcome.task, record: outcome.record, time: WowFixture.time(10, 1)))
        #expect(undone.task.cancelledAt == nil)
        #expect(undone.task.date == tasks[0].date)
        #expect(undone.record?.feedback.last?.kind == .taskRestored(taskID: tasks[0].id))
        #expect(feedback.undo(tasks[0], record: nil, time: time) == nil, "Неотменённую возвращать незачем")
    }

    @Test("Вопрос записан в день: Linea помнит, что спрашивала")
    func askedIsRecorded() throws {
        let time = WowFixture.time(10)
        let day = record(tasks, at: time)
        let question = try #require(feedback.question(for: tasks[0], record: day, tasks: tasks, calibration: .default, time: time))
        let asked = feedback.asking(question, in: day, at: time.now)
        #expect(asked.feedback.last?.kind == .notNowAsked(taskID: tasks[0].id))
        #expect(asked.notNowQuestions.map(\.taskID) == [tasks[0].id])
    }
}
