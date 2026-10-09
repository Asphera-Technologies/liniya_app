import Testing
import Foundation
@testable import LineaCore

/// Состояния задачи и выполнение: внутри — семь состояний, у человека — три
/// действия («Начать», «Завершить», «Не сейчас»), а в данных — что было на
/// самом деле. Среда 9 сентября 2026, Москва.
@Suite("Состояния задачи и выполнение")
struct TaskExecutionTests {
    private let execution = TaskExecutionUseCase()
    private let lifecycle = TaskLifecycle()
    private let nextAction = NextActionUseCase(renderer: RuleBasedExplainer())

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "5C000000-0000-0000-0000-%012d", n))!
    }

    private var errands: [LineaTask] {
        ["Ответить клиенту", "Проверить сборку", "Разобрать письмо", "Оплатить интернет"].enumerated().map { index, title in
            LineaTask(id: id(index + 1), title: title, date: WowFixture.today,
                      priority: index == 0 ? .important : .normal,
                      createdAt: WowFixture.created.addingTimeInterval(TimeInterval(index * 60)), estimatedMinutes: 15)
        }
    }

    private func record(_ tasks: [LineaTask], at time: TimeContext) -> DayRecord {
        DayRecord(day: WowFixture.today, snapshot: PlanFixture.snapshot(tasks: tasks, commitments: [], goals: [], at: time),
                  state: PlanFixture.state(energy: 0.6, confidence: 0.9, advice: .normal, at: time), updatedAt: time.now)
    }

    private func feedbackKinds(_ record: DayRecord?) -> [FeedbackKind] {
        record?.feedback.map(\.kind) ?? []
    }

    // MARK: Состояния

    @Test("Семь состояний выводятся из того, что было с задачей")
    func statuses() {
        let now = WowFixture.moment(10)
        let inbox = LineaTask(title: "Посмотреть AI-модели", createdAt: WowFixture.created)
        #expect(inbox.status(at: now) == .inbox)
        #expect(LineaTask(title: "Отчёт", date: WowFixture.today, createdAt: WowFixture.created).status(at: now) == .planned)
        #expect(LineaTask(title: "Отчёт", createdAt: WowFixture.created, deadline: WowFixture.moment(18)).status(at: now) == .planned)
        #expect(inbox.status(at: now, isSuggested: true) == .suggested)

        var task = LineaTask(title: "Отчёт", date: WowFixture.today, createdAt: WowFixture.created)
        task.startedAt = now
        #expect(task.status(at: now, isSuggested: true) == .started, "Начатая — начата, даже если её же предлагают")
        task.isDone = true
        #expect(task.status(at: now) == .completed)
        var later = inbox
        later.deferredUntil = WowFixture.moment(11, 30)
        #expect(later.status(at: now) == .deferred)
        #expect(later.status(at: WowFixture.moment(11, 30)) == .inbox, "«Не сейчас» прошло — снова во входящих")
        var cancelled = task
        cancelled.cancelledAt = now
        #expect(cancelled.status(at: now) == .cancelled, "Отменённая — отменена, даже если сделана")
        #expect(TaskStatus.allCases.count == 7)
    }

    @Test("Человек видит выполнение одной строкой, без внутренних состояний")
    func statusText() throws {
        let time = WowFixture.time(12)
        var task = errands[0]
        #expect(TaskExecutionText.status(of: task, time: time) == nil, "Запланирована — сказать нечего")
        #expect(TaskExecutionText.caption(of: task, time: time) == nil)

        task.startedAt = WowFixture.moment(10, 12)
        #expect(TaskExecutionText.status(of: task, time: time) == "В работе с 10:12")
        #expect(TaskExecutionText.caption(of: task, time: time) == "В работе с 10:12")
        task.startedAt = WowFixture.moment(17, 5, dayOffset: -1)
        #expect(TaskExecutionText.status(of: task, time: time) == "Начата вчера в 17:05")

        let started = try #require(lifecycle.start(errands[0], suggestionID: nil, at: WowFixture.moment(10, 30)))
        let finished = try #require(lifecycle.finish(started, suggestionID: nil, at: WowFixture.moment(11, 5)))
        #expect(TaskExecutionText.status(of: finished, time: time) == "Сделано в 11:05 · за 35 мин")
        #expect(TaskExecutionText.caption(of: finished, time: time) == nil, "Сделанную видно по галочке")
        var long = finished
        long.actualMinutes = 95
        #expect(TaskExecutionText.status(of: long, time: time) == "Сделано в 11:05 · за 1 ч 35 мин")
        var direct = errands[0]
        direct.isDone = true
        direct.completedAt = WowFixture.moment(9, 0, dayOffset: -3)
        #expect(TaskExecutionText.status(of: direct, time: time) == "Сделано в вс, 6 сен")

        let deferred = try #require(lifecycle.notNow(errands[0], at: WowFixture.moment(11)))
        #expect(TaskExecutionText.status(of: deferred, time: time) == "Не сейчас — до 12:30")
        #expect(TaskExecutionText.caption(of: deferred, time: time) == "Не сейчас — до 12:30")
        #expect(TaskExecutionText.status(of: deferred, time: WowFixture.time(12, 30)) == nil, "Прошло — снова обычная")
        let late = try #require(lifecycle.notNow(errands[0], at: WowFixture.moment(23, 15)))
        #expect(TaskExecutionText.status(of: late, time: WowFixture.time(23, 20)) == "Не сейчас — до завтра, 0:45")
    }

    // MARK: Переходы

    @Test("«Начать»: время начала и принятое предложение; сделанную и отменённую не начать")
    func start() throws {
        let now = WowFixture.moment(10)
        var task = errands[0]
        task.deferredUntil = WowFixture.moment(10, 30)
        let started = try #require(lifecycle.start(task, suggestionID: id(90), at: now))
        #expect(started.startedAt == now)
        #expect(started.suggestionID == id(90))
        #expect(started.deferredUntil == nil)

        var done = errands[0]
        done.isDone = true
        #expect(lifecycle.start(done, suggestionID: nil, at: now) == nil)
        var cancelled = errands[0]
        cancelled.cancelledAt = now
        #expect(lifecycle.start(cancelled, suggestionID: nil, at: now) == nil)
    }

    @Test("«Завершить»: время и сколько заняло на самом деле — если начинали")
    func finish() throws {
        let started = try #require(lifecycle.start(errands[0], suggestionID: nil, at: WowFixture.moment(10)))
        let finished = try #require(lifecycle.finish(started, suggestionID: nil, at: WowFixture.moment(10, 35)))
        #expect(finished.isDone)
        #expect(finished.completedAt == WowFixture.moment(10, 35))
        #expect(finished.actualMinutes == 35)
        #expect(finished.status(at: WowFixture.moment(11)) == .completed)
        #expect(lifecycle.finish(finished, suggestionID: nil, at: WowFixture.moment(11)) == nil, "Дважды не завершить")

        // Не начинали — сколько заняло, неизвестно.
        let direct = try #require(lifecycle.finish(errands[1], suggestionID: nil, at: WowFixture.moment(10)))
        #expect(direct.actualMinutes == nil)
        // Забыли завершить — больше 12 часов не правда.
        let forgotten = try #require(lifecycle.finish(started, suggestionID: nil, at: WowFixture.moment(10, 0, dayOffset: 1)))
        #expect(forgotten.actualMinutes == nil)
        #expect(TaskLifecycle.actualMinutes(from: WowFixture.moment(10), to: WowFixture.moment(10, 0)) == 1)
        #expect(TaskLifecycle.actualMinutes(from: WowFixture.moment(10), to: WowFixture.moment(9)) == nil)
    }

    @Test("«Не сейчас»: полтора часа без предложений, начатая — больше не начата")
    func notNow() throws {
        let now = WowFixture.moment(10)
        let started = try #require(lifecycle.start(errands[0], suggestionID: id(90), at: now))
        let deferred = try #require(lifecycle.notNow(started, at: WowFixture.moment(10, 5)))
        #expect(deferred.startedAt == nil)
        #expect(deferred.suggestionID == nil)
        #expect(deferred.deferredUntil == WowFixture.moment(11, 35))
        #expect(deferred.status(at: WowFixture.moment(11)) == .deferred)
        #expect(deferred.status(at: WowFixture.moment(11, 35)) == .planned)
    }

    @Test("Отменить и вернуть закрытую")
    func cancelAndReopen() throws {
        let now = WowFixture.moment(10)
        let cancelled = try #require(lifecycle.cancel(errands[0], at: now))
        #expect(cancelled.cancelledAt == now)
        #expect(!cancelled.isOpen)
        #expect(lifecycle.cancel(cancelled, at: now) == nil)

        let started = try #require(lifecycle.start(errands[0], suggestionID: id(90), at: now))
        let finished = try #require(lifecycle.finish(started, suggestionID: nil, at: WowFixture.moment(10, 20)))
        let reopened = try #require(lifecycle.reopen(finished))
        #expect(!reopened.isDone)
        #expect(reopened.completedAt == nil)
        #expect(reopened.actualMinutes == nil)
        #expect(reopened.startedAt == nil)
        #expect(reopened.suggestionID == nil)
        #expect(reopened.status(at: now) == .planned)
        #expect(lifecycle.reopen(errands[0]) == nil, "Открытую не вернуть")
    }

    // MARK: Предложения

    @Test("Журнал предложений: одно на задачу, пока её предлагают; сменилась — прежнее без ответа")
    func suggestionTracking() throws {
        let time = WowFixture.time(10)
        let tasks = errands
        let first = try #require(nextAction.run(record: record(tasks, at: time), tasks: tasks, calibration: .default, time: time))
        var day = SuggestionLog.tracking(first, newID: id(90), isAlternative: false, in: record(tasks, at: time), at: time.now)
        #expect(day.suggestions.count == 1)
        let suggestion = try #require(day.suggestions.first)
        #expect(suggestion.taskID == first.taskID)
        #expect(suggestion.isOpen)
        #expect(suggestion.accepted == nil)
        #expect(suggestion.reason == .highPriority, "Причина та же, что видел человек")

        // Та же задача минуту спустя — то же предложение.
        day = SuggestionLog.tracking(first, newID: id(91), isAlternative: false, in: day, at: WowFixture.moment(10, 1))
        #expect(day.suggestions.count == 1)

        // Другая задача — прежнее закрыто без ответа.
        let other = NextAction(option: NextAction.Option(taskID: id(2), title: "Проверить сборку", minutes: 15),
                               alternatives: [], laterTaskID: nil, startedAt: nil, headline: "", reason: "", facts: [])
        day = SuggestionLog.tracking(other, newID: id(92), isAlternative: false, in: day, at: WowFixture.moment(10, 2))
        #expect(day.suggestions.map(\.response) == [.replaced, nil])
        #expect(day.suggestions.first?.accepted == false)

        // Пустое «Сейчас» (встреча) закрывает открытое.
        day = SuggestionLog.tracking(nil, newID: id(93), isAlternative: false, in: day, at: WowFixture.moment(10, 3))
        #expect(day.suggestions.map(\.response) == [.replaced, .replaced])
        #expect(SuggestionLog.open(in: day) == nil)

        // Ответа на задачу без открытого предложения нет — день не меняется.
        let none = SuggestionLog.responding(.accepted, to: id(1), in: day, at: WowFixture.moment(10, 4))
        #expect(none.suggestionID == nil)
        #expect(none.record.suggestions == day.suggestions)
    }

    @Test("Пересчёт дня, идущий одновременно с ответом, не теряет ни предложений, ни ответов")
    func suggestionsMerge() {
        let at = WowFixture.moment(10)
        let read = [TaskSuggestion(id: id(90), taskID: id(1), suggestedAt: at)]
        let memory = [
            TaskSuggestion(id: id(90), taskID: id(1), suggestedAt: at, response: .replaced, respondedAt: WowFixture.moment(10, 5)),
            TaskSuggestion(id: id(91), taskID: id(2), suggestedAt: WowFixture.moment(10, 5)),
        ]
        #expect(SuggestionLog.merged(read, with: memory) == memory)
        // Ответ сильнее его отсутствия — в какую сторону ни сливай.
        #expect(SuggestionLog.merged(memory, with: read) == memory)
        #expect(SuggestionLog.merged(memory, with: []) == memory)
        #expect(SuggestionLog.merged([], with: memory) == memory)
    }

    // MARK: Сценарий заказчика

    @Test("Предложено → «Начать» → «Завершить»: suggestion_id, accepted = true, started_at, completed_at, actual_duration")
    func suggestedStartFinish() throws {
        let time = WowFixture.time(10)
        var tasks = errands
        let action = try #require(nextAction.run(record: record(tasks, at: time), tasks: tasks, calibration: .default, time: time))
        let option = try #require(action.option)
        var day = SuggestionLog.tracking(action, newID: id(90), isAlternative: false, in: record(tasks, at: time), at: time.now)
        let index = try #require(tasks.firstIndex { $0.id == option.taskID })
        #expect(tasks[index].status(at: time.now, isSuggested: true) == .suggested)

        // «Начать».
        let started = try #require(execution.run(.start, task: tasks[index], record: day, plannedMinutes: option.minutes, at: time.now))
        tasks[index] = started.task
        day = try #require(started.record)
        #expect(started.task.startedAt == time.now)
        #expect(started.task.suggestionID == id(90))
        #expect(day.suggestions.first?.accepted == true)
        #expect(day.suggestions.first?.respondedAt == time.now)
        #expect(feedbackKinds(day) == [.actionStarted(ActionStart(taskID: option.taskID, minutes: 15, wasAlternative: false, suggestionID: id(90)))])
        #expect(started.task.status(at: time.now) == .started)

        // Начатое — «в работе» в «Сейчас», новых предложений не появляется.
        let during = try #require(nextAction.run(record: day, tasks: tasks, calibration: .default, time: WowFixture.time(10, 20)))
        #expect(during.isStarted)
        day = SuggestionLog.tracking(during, newID: id(91), isAlternative: false, in: day, at: WowFixture.moment(10, 20))
        #expect(day.suggestions.count == 1)

        // «Завершить» через 35 минут.
        let finished = try #require(execution.run(.finish, task: tasks[index], record: day, plannedMinutes: 15, at: WowFixture.moment(10, 35)))
        #expect(finished.task.completedAt == WowFixture.moment(10, 35))
        #expect(finished.task.actualMinutes == 35)
        #expect(finished.task.suggestionID == id(90))
        #expect(finished.task.status(at: WowFixture.moment(10, 35)) == .completed)
        let last = try #require(finished.record?.feedback.last?.kind)
        #expect(last == .taskFinished(TaskFinish(taskID: option.taskID, actualMinutes: 35, plannedMinutes: 15, suggestionID: id(90))))
        #expect(finished.record?.feedback.last?.energy == 0.6, "Отклик хранит, каким Linea видела человека")
    }

    @Test("«Не сейчас» на предложении: отказ, и Linea полтора часа предлагает другое")
    func notNowOnSuggestion() throws {
        let time = WowFixture.time(10)
        var tasks = errands
        let action = try #require(nextAction.run(record: record(tasks, at: time), tasks: tasks, calibration: .default, time: time))
        let declinedID = try #require(action.taskID)
        var day = SuggestionLog.tracking(action, newID: id(90), isAlternative: false, in: record(tasks, at: time), at: time.now)

        let index = try #require(tasks.firstIndex { $0.id == declinedID })
        let output = try #require(execution.run(.notNow, task: tasks[index], record: day, plannedMinutes: 15, at: time.now))
        tasks[index] = output.task
        day = try #require(output.record)
        #expect(day.suggestions.first?.response == .declined)
        #expect(day.suggestions.first?.accepted == false)
        #expect(feedbackKinds(day) == [.taskNotNow(taskID: declinedID, wasStarted: false)])

        let next = try #require(nextAction.run(record: day, tasks: tasks, calibration: .default, time: WowFixture.time(10, 1)))
        #expect(next.taskID != declinedID)
        #expect(!next.alternatives.contains { $0.taskID == declinedID }, "Отложенную не предлагают и в «Другое»")
        let back = try #require(nextAction.run(record: day, tasks: tasks, calibration: .default, time: WowFixture.time(11, 31)))
        #expect(back.taskID == declinedID, "Полтора часа прошли — снова можно")
    }

    @Test("«Другое»: выбор — не отказ и не согласие; принятый вариант помечен")
    func alternativeChosen() throws {
        let time = WowFixture.time(10)
        let tasks = errands
        let action = try #require(nextAction.run(record: record(tasks, at: time), tasks: tasks, calibration: .default, time: time))
        let main = try #require(action.taskID)
        let chosen = try #require(action.alternatives.first)
        var day = SuggestionLog.tracking(action, newID: id(90), isAlternative: false, in: record(tasks, at: time), at: time.now)
        day = SuggestionLog.responding(.otherChosen, to: main, in: day, at: WowFixture.moment(10, 1)).record
        let preferred = try #require(nextAction.run(record: day, tasks: tasks, calibration: .default,
                                                    time: WowFixture.time(10, 1), preferred: chosen.taskID))
        day = SuggestionLog.tracking(preferred, newID: id(91), isAlternative: true, in: day, at: WowFixture.moment(10, 1))
        #expect(day.suggestions.map(\.response) == [.otherChosen, nil])
        #expect(day.suggestions.last?.isAlternative == true)

        let task = try #require(tasks.first { $0.id == chosen.taskID })
        let started = try #require(execution.run(.start, task: task, record: day, plannedMinutes: chosen.minutes, at: WowFixture.moment(10, 2)))
        #expect(started.record?.suggestions.last?.accepted == true)
        #expect(feedbackKinds(started.record).last == .actionStarted(ActionStart(
            taskID: chosen.taskID, minutes: 15, wasAlternative: true, suggestionID: id(91))))
    }

    @Test("Взялся за другое сам или сразу сделал предложенное")
    func otherStartsAndDirectFinish() throws {
        let time = WowFixture.time(10)
        let tasks = errands
        let action = try #require(nextAction.run(record: record(tasks, at: time), tasks: tasks, calibration: .default, time: time))
        let main = try #require(action.taskID)
        let day = SuggestionLog.tracking(action, newID: id(90), isAlternative: false, in: record(tasks, at: time), at: time.now)

        // Начал из списка другое дело — предложение «выбрано иное», у начала нет id.
        let other = try #require(tasks.first { $0.id != main })
        let started = try #require(execution.run(.start, task: other, record: day, plannedMinutes: 15, at: time.now))
        #expect(started.record?.suggestions.first?.response == .otherChosen)
        #expect(started.task.suggestionID == nil)

        // Сразу сделал предложенное (свайпом) — принято, хоть и без «Начать».
        let suggested = try #require(tasks.first { $0.id == main })
        let done = try #require(execution.run(.finish, task: suggested, record: day, plannedMinutes: 15, at: time.now))
        #expect(done.record?.suggestions.first?.accepted == true)
        #expect(done.task.suggestionID == id(90))
        #expect(done.task.actualMinutes == nil, "Не начинали — сколько заняло, неизвестно")
    }

    @Test("Отведённое время вышло, а задача начата — «Сейчас» показывает её в работе, а не «Начать» заново")
    func overrunStaysStarted() throws {
        let time = WowFixture.time(10)
        var tasks = errands
        let action = try #require(nextAction.run(record: record(tasks, at: time), tasks: tasks, calibration: .default, time: time))
        let index = try #require(tasks.firstIndex { $0.id == action.taskID })
        let output = try #require(execution.run(.start, task: tasks[index], record: record(tasks, at: time),
                                                plannedMinutes: 15, at: time.now))
        tasks[index] = output.task
        let day = try #require(output.record)
        // 15 минут отведено, действие «идёт» до 10:30; в 10:40 Linea снова выбирает её.
        #expect(day.activeAction(tasks: tasks, at: WowFixture.moment(10, 40)) == nil)
        let later = try #require(nextAction.run(record: day, tasks: tasks, calibration: .default, time: WowFixture.time(10, 40)))
        #expect(later.taskID == tasks[index].id)
        #expect(later.isStarted, "Всё ещё в работе")
        #expect(later.startedAt == time.now, "Время начала прежнее")
        #expect(later.facts.contains(.actionStarted(at: time.now, minutes: 15)))
        #expect(!later.alternatives.contains { $0.taskID == tasks[index].id })
        // Журнал не считает это новым предложением.
        #expect(SuggestionLog.tracking(later, newID: id(91), isAlternative: false, in: day, at: WowFixture.moment(10, 40))
            .suggestions == day.suggestions)
    }

    @Test("В работе одно дело: «Начать» другое снимает с работы прежнее, не откладывая")
    func oneStartedAtATime() throws {
        let time = WowFixture.time(10)
        var tasks = errands
        let action = try #require(nextAction.run(record: record(tasks, at: time), tasks: tasks, calibration: .default, time: time))
        let main = try #require(tasks.firstIndex { $0.id == action.taskID })
        var day = SuggestionLog.tracking(action, newID: id(90), isAlternative: false, in: record(tasks, at: time), at: time.now)
        let first = try #require(execution.run(.start, task: tasks[main], others: tasks, record: day,
                                               plannedMinutes: 15, at: time.now))
        #expect(first.paused.isEmpty, "Начатых не было — снимать нечего")
        tasks[main] = first.task
        day = try #require(first.record)

        let other = try #require(tasks.firstIndex { $0.id != tasks[main].id })
        let second = try #require(execution.run(.start, task: tasks[other], others: tasks, record: day,
                                                plannedMinutes: 15, at: WowFixture.moment(10, 10)))
        let paused = try #require(second.paused.first)
        #expect(second.paused.count == 1)
        #expect(paused.id == tasks[main].id)
        #expect(paused.startedAt == nil)
        #expect(paused.deferredUntil == nil, "Снятая с работы не откладывается")
        #expect(paused.suggestionID == id(90), "От предложения не отказывались — связь остаётся")
        #expect(paused.status(at: WowFixture.moment(10, 10)) == .planned)
        for updated in [second.task] + second.paused {
            tasks[tasks.firstIndex { $0.id == updated.id }!] = updated
        }
        let active = try #require(second.record?.activeAction(tasks: tasks, at: WowFixture.moment(10, 11)))
        #expect(active.start.taskID == tasks[other].id)
        #expect(tasks.filter { $0.status(at: WowFixture.moment(10, 11)) == .started }.map(\.id) == [tasks[other].id])
        #expect(lifecycle.pause(errands[0]) == nil, "Не начатую не снять")
    }

    @Test("Убрать из планов: отказ от предложения, отклик, и задачи больше нет в плане")
    func cancelSuggested() throws {
        let time = WowFixture.time(10)
        var tasks = errands
        let action = try #require(nextAction.run(record: record(tasks, at: time), tasks: tasks, calibration: .default, time: time))
        let main = try #require(action.taskID)
        let day = SuggestionLog.tracking(action, newID: id(90), isAlternative: false, in: record(tasks, at: time), at: time.now)
        let index = try #require(tasks.firstIndex { $0.id == main })
        let output = try #require(execution.run(.cancel, task: tasks[index], record: day, plannedMinutes: 15, at: time.now))
        tasks[index] = output.task
        #expect(output.record?.suggestions.first?.response == .declined)
        #expect(feedbackKinds(output.record) == [.taskCancelled(taskID: main)])
        #expect(output.task.status(at: time.now) == .cancelled)

        let context = PriorityContext(snapshot: PlanFixture.snapshot(tasks: tasks, commitments: [], goals: [], at: time),
                                      state: PlanFixture.state(energy: 0.6, confidence: 0.9, advice: .normal, at: time), time: time)
        #expect(!PriorityEngine().candidates(context: context).contains { $0.id == main })
        var inbox = output.task
        inbox.date = nil
        #expect(!InboxReview.isInInbox(inbox), "Отменённой нет и во входящих")
    }

    @Test("Вернуть по ошибке закрытую — в журнале отметка, что завершение не в силе")
    func reopenUndoesFinish() throws {
        let time = WowFixture.time(10)
        let day = record(errands, at: time)
        let finished = try #require(execution.run(.finish, task: errands[1], record: day, plannedMinutes: 15, at: time.now))
        #expect(feedbackKinds(finished.record).count == 1)
        let reopened = try #require(execution.run(.reopen, task: finished.task, record: finished.record,
                                                  plannedMinutes: 15, at: WowFixture.moment(10, 1)))
        #expect(!reopened.task.isDone)
        // Журнал только дописывается: так его не сломает пересчёт дня, идущий одновременно.
        #expect(feedbackKinds(reopened.record) == [
            .taskFinished(TaskFinish(taskID: errands[1].id, actualMinutes: nil, plannedMinutes: 15, suggestionID: nil)),
            .taskReopened(taskID: errands[1].id),
        ])
        // Недопустимый переход ничего не меняет.
        #expect(execution.run(.reopen, task: errands[1], record: day, plannedMinutes: 15, at: time.now) == nil)
        // Записи дня ещё нет — меняется только задача.
        #expect(execution.run(.start, task: errands[1], record: nil, plannedMinutes: 15, at: time.now)?.record == nil)
    }

    // MARK: План и документ дня

    @Test("План не ставит отложенную задачу раньше, чем кончится «Не сейчас»")
    func planRespectsNotNow() throws {
        let time = WowFixture.time(10)
        var tasks = errands
        tasks[0].deferredUntil = WowFixture.moment(11, 30)
        let plan = PlanFixture.engine().plan(
            snapshot: PlanFixture.snapshot(tasks: tasks, commitments: [], goals: [], at: time),
            state: PlanFixture.state(energy: 0.6, confidence: 0.9, advice: .normal, at: time),
            calibration: .default, time: time, planID: WowFixture.planID
        )
        let block = try #require(plan.blocks.first { $0.taskID == tasks[0].id })
        #expect(block.start >= WowFixture.moment(11, 30))
    }

    @Test("Предложения переживают пересчёт дня и старые записи без них")
    func suggestionsPersist() async throws {
        let time = WowFixture.time(10)
        let suggestion = TaskSuggestion(id: id(90), taskID: id(1), suggestedAt: time.now, reason: .highPriority,
                                        response: .accepted, respondedAt: time.now)
        let existing = DayRecord(day: WowFixture.today, suggestions: [suggestion], updatedAt: time.now)
        let planDay = PlanDayUseCase(
            contextEngine: ContextEngine(providers: []), decisionEngine: PlanFixture.engine(),
            nudgeEngine: PlanFixture.nudgeEngine(), explainer: RuleBasedExplainer()
        )
        let output = await planDay.run(PlanDayUseCase.Input(
            time: WowFixture.time(10, 5), tasks: errands, goals: [], existing: existing, allowsRemoteExplanation: false
        ))
        #expect(output.record.suggestions == [suggestion])

        let encoder = JSONEncoder()
        let data = try encoder.encode(output.record)
        let decoded = try JSONDecoder().decode(DayRecord.self, from: data)
        #expect(decoded.suggestions == [suggestion])
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "suggestions")
        let legacy = try JSONDecoder().decode(DayRecord.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.suggestions.isEmpty)
        #expect(legacy.plan?.id == output.record.plan?.id)

        // Задача, записанная до этого этапа, читается без полей выполнения.
        let task = LineaTask(title: "Отчёт", createdAt: WowFixture.created, startedAt: time.now, actualMinutes: 20,
                             suggestionID: id(90), deferredUntil: time.now, cancelledAt: time.now)
        let taskData = try encoder.encode(task)
        #expect(try JSONDecoder().decode(LineaTask.self, from: taskData) == task)
        var taskJSON = try #require(try JSONSerialization.jsonObject(with: taskData) as? [String: Any])
        for key in ["startedAt", "actualMinutes", "suggestionID", "deferredUntil", "cancelledAt"] { taskJSON.removeValue(forKey: key) }
        let old = try JSONDecoder().decode(LineaTask.self, from: JSONSerialization.data(withJSONObject: taskJSON))
        #expect(old.startedAt == nil)
        #expect(old.cancelledAt == nil)
        #expect(old.isOpen)
    }
}
