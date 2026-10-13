import Testing
import Foundation
@testable import LineaCore

/// «Позже сегодня» и «Пусть Linea решит»: Linea сама находит задаче окно.
/// Среда 9 сентября 2026, Москва, рабочий день 9–21, обед 13:00–13:40.
@Suite("Перенести: позже сегодня и «Пусть Linea решит»")
struct AutoRescheduleTests {
    private let reschedule = TaskReschedule()
    private let auto = AutoReschedule()

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "A0700000-0000-0000-0000-%012d", n))!
    }

    private func task(_ n: Int = 1, _ title: String = "Подготовить презентацию", date: Date? = WowFixture.today,
                      minutes: Int = 45, demand: CognitiveDemand = .normal, deadline: Date? = nil) -> LineaTask {
        LineaTask(id: id(n), title: title, date: date, createdAt: WowFixture.created, deadline: deadline,
                  estimatedMinutes: minutes, cognitiveDemand: demand, userFields: [.day, .duration])
    }

    private func meeting(_ hour: Int, _ minute: Int = 0, until endHour: Int, _ endMinute: Int = 0,
                         dayOffset: Int = 0) -> Commitment {
        Commitment(id: "meeting-\(dayOffset)-\(hour)-\(minute)", title: "Встреча",
                   start: WowFixture.moment(hour, minute, dayOffset: dayOffset),
                   end: WowFixture.moment(endHour, endMinute, dayOffset: dayOffset), kind: .meeting, source: .calendar)
    }

    private func context(_ tasks: [LineaTask], commitments: [Commitment] = [],
                         at time: TimeContext = WowFixture.time(10)) -> RescheduleContext {
        RescheduleContext(profile: WowFixture.profile, tasks: tasks, commitments: commitments,
                          nutrition: WowFixture.nutrition, time: time)
    }

    // MARK: Позже сегодня

    @Test("«Позже сегодня»: не раньше чем через полтора часа — в окно, где задача помещается целиком")
    func laterToday() throws {
        let time = WowFixture.time(10)
        // Встреча 11:30–13:00, обед 13:00–13:40 — первое окно на 45 минут — с 13:40.
        let result = reschedule.apply(.laterToday, to: task(), context: context([task()], commitments: [meeting(11, 30, until: 13)]))
        #expect(result.task.date == WowFixture.today)
        #expect(result.task.deferredUntil == WowFixture.moment(13, 40))
        #expect(result.task.rescheduleMode == .laterToday)
        #expect(result.task.status(at: time.now) == .deferred)
        #expect(result.note == "Перенесла на 13:40.")
        #expect(TaskExecutionText.caption(of: result.task, time: time) == "Позже — с 13:40")

        // Из «Без даты» — на сегодня и уже разобрана.
        let inbox = reschedule.apply(.laterToday, to: task(date: nil), context: context([]))
        #expect(inbox.task.date == WowFixture.today)
        #expect(inbox.task.inboxReviewedAt == time.now)
        #expect(inbox.task.deferredUntil == WowFixture.moment(11, 30))
    }

    @Test("«Позже сегодня» у задачи со своим временем: время снято, своё же время окну не мешает")
    func laterTodayFixedTask() throws {
        var fixed = task()
        fixed.scheduledStart = WowFixture.moment(11, 30)
        let result = reschedule.apply(.laterToday, to: fixed, context: context([fixed]))
        #expect(result.task.scheduledStart == nil, "Иначе задача ждала бы своего времени и «позже» — сразу")
        #expect(result.task.deferredUntil == WowFixture.moment(11, 30))
        let decided = reschedule.apply(.automatic, to: fixed, context: context([fixed])).task
        #expect(decided.deferredUntil == WowFixture.moment(11, 30))
    }

    @Test("Обычные переносы говорят коротко, куда, и снимают «Не сейчас» и «в работе»")
    func simpleTargetsNote() {
        var started = task()
        started.startedAt = WowFixture.moment(9, 40)
        started.deferredUntil = WowFixture.moment(11)
        let tomorrow = reschedule.apply(.tomorrow, to: started, context: context([started]))
        #expect(tomorrow.note == "Перенесла на завтра.")
        #expect(tomorrow.task.startedAt == nil)
        #expect(tomorrow.task.deferredUntil == nil)
        #expect(reschedule.apply(.thisWeek, to: task(), context: context([])).note == "Перенесла на эту неделю — до вс, 13 сен.")
        #expect(reschedule.apply(.day(WowFixture.moment(12, 0, dayOffset: 2)), to: task(), context: context([])).note
                == "Перенесла на пт, 11 сен.")
        #expect(reschedule.apply(.today, to: task(date: WowFixture.moment(12, 0, dayOffset: 2)), context: context([])).note
                == "Перенесла на сегодня.")
    }

    // MARK: Пусть Linea решит

    @Test("«Пусть Linea решит»: deferred = true, reschedule_mode = automatic, день и время — решение Linea")
    func customerFields() throws {
        let time = WowFixture.time(10)
        let original = task()
        let result = reschedule.apply(.automatic, to: original, context: context([original]))
        #expect(result.task.rescheduleMode == .automatic)
        #expect(result.task.status(at: time.now) == .deferred, "deferred = true")
        #expect(result.task.date == WowFixture.today)
        #expect(result.task.deferredUntil == WowFixture.moment(11, 30), "Не раньше чем через полтора часа")
        #expect(!result.task.isSetByUser(.day), "День теперь выбирает Linea")
        #expect(!result.task.isSetByUser(.startTime))
        #expect(result.task.isSetByUser(.duration), "Остальное, что задал человек, — его")
        #expect(result.note == "Поставила на сегодня, 11:30.")
        #expect(TaskExecutionText.status(of: result.task, time: time) == "Время выбрала Linea: 11:30")

        // Задача, сохранённая раньше, чем Linea стала помнить, чьё что: всё —
        // человека, кроме дня и времени, которые он отдал Linea.
        var legacy = original
        legacy.userFields = nil
        let fromLegacy = reschedule.apply(.automatic, to: legacy, context: context([legacy])).task
        #expect(fromLegacy.userFields == Set(TaskField.allCases).subtracting([.day, .startTime]))
    }

    @Test("Сложное — с утра, лёгкое — после обеда, обычное — в первое окно")
    func demandPicksWindow() throws {
        let deep = reschedule.apply(.automatic, to: task(1, minutes: 60, demand: .deep), context: context([]))
        #expect(deep.task.deferredUntil == WowFixture.moment(11, 30))
        let light = reschedule.apply(.automatic, to: task(2, "Оплатить интернет", minutes: 15, demand: .light), context: context([]))
        #expect(light.task.deferredUntil == WowFixture.moment(13, 40), "Утро — для сложного")
        let normal = reschedule.apply(.automatic, to: task(3, "Ответить на письма", minutes: 30), context: context([]))
        #expect(normal.task.deferredUntil == WowFixture.moment(11, 30))
    }

    @Test("Сегодня окна нет — завтра; на завтра встречи из календаря — после них")
    func nextDayAroundCalendar() throws {
        // Сегодня встречи с 11:00 до конца рабочего дня, завтра — 9:00–11:00.
        let busy = [meeting(11, until: 21), meeting(9, until: 11, dayOffset: 1)]
        let result = reschedule.apply(.automatic, to: task(demand: .deep), context: context([task()], commitments: busy))
        #expect(result.task.date == WowFixture.moment(0, 0, dayOffset: 1))
        #expect(result.task.deferredUntil == WowFixture.moment(11, 0, dayOffset: 1))
        #expect(result.note == "Поставила на завтра, 11:00.")
        #expect(TaskExecutionText.status(of: result.task, time: WowFixture.time(10)) == "Время выбрала Linea: завтра, 11:00")
    }

    @Test("Учитывает, что на день уже стоит: полный день — дальше")
    func skipsFullDays() throws {
        let evening = WowFixture.time(20)
        // На завтра уже 12 часовых дел — больше, чем свободного времени.
        let tomorrowLoad = (10..<22).map { task($0, "Дело \($0)", date: WowFixture.moment(0, 0, dayOffset: 1), minutes: 60) }
        let result = reschedule.apply(.automatic, to: task(), context: context([task()] + tomorrowLoad, at: evening))
        #expect(result.task.date == WowFixture.moment(0, 0, dayOffset: 2))
        #expect(result.task.deferredUntil == WowFixture.moment(9, 0, dayOffset: 2))
        #expect(result.note == "Поставила на пт, 11 сен, 9:00.")
    }

    @Test("Срок впереди: окно — так, чтобы успеть к сроку")
    func respectsDeadline() throws {
        // Срок — завтра в 12:00; сегодня занято, завтра встреча до 10:30.
        let due = task(minutes: 60, deadline: WowFixture.moment(12, 0, dayOffset: 1))
        let busy = [meeting(11, until: 21), meeting(9, until: 10, 30, dayOffset: 1)]
        let result = reschedule.apply(.automatic, to: due, context: context([due], commitments: busy))
        #expect(result.task.deferredUntil == WowFixture.moment(10, 30, dayOffset: 1))
        #expect(result.task.deadline == due.deadline, "Срок — обещание, Linea его не двигает")

        // Целиком нигде не помещается — сегодня, время найдёт план.
        let huge = task(minutes: 600, deadline: WowFixture.moment(12, 0, dayOffset: 1))
        let impossible = reschedule.apply(.automatic, to: huge, context: context([huge], commitments: busy))
        #expect(impossible.task.date == WowFixture.today)
        #expect(impossible.task.deferredUntil == WowFixture.moment(11, 30))
        #expect(impossible.note == "Поставила на сегодня — время найдёт план.")
    }

    @Test("День прошёл, а задача не сделана — Linea сама находит новое окно, без «просрочено»")
    func missedDayIsReplaced() throws {
        let time = WowFixture.time(10)
        let decided = reschedule.apply(.automatic, to: task(), context: context([task()], at: WowFixture.time(10, 0, dayOffset: -1))).task
        #expect(decided.date == WowFixture.moment(0, 0, dayOffset: -1))
        var started = decided
        started.startedAt = WowFixture.moment(9, 30)
        var done = task(2, "Сделано", date: WowFixture.moment(0, 0, dayOffset: -1))
        done.rescheduleMode = .automatic
        done.isDone = true
        let manual = task(3, "Своя", date: WowFixture.moment(0, 0, dayOffset: -1))

        let moved = auto.replacingMissed(context: context([decided, done, manual], at: time))
        #expect(moved.map(\.id) == [decided.id], "Сделанные и поставленные человеком Linea не трогает")
        let replaced = try #require(moved.first)
        #expect(replaced.date == WowFixture.today)
        #expect(replaced.deferredUntil == nil, "Окно есть прямо сейчас")
        #expect(replaced.rescheduleMode == .automatic)
        #expect(TaskDeferral.counted(previous: decided, updated: replaced, time: time).deferralCount == 1,
                "Задача зависает — Linea это видит")
        #expect(auto.replacingMissed(context: context([started], at: time)).isEmpty, "Начатую не трогает")
    }

    @Test("Человек сам поставил день — выбор снова за ним: режим снят, день — его")
    func userTakesBack() throws {
        let decided = reschedule.apply(.automatic, to: task(), context: context([task()])).task
        var edited = decided
        edited.date = WowFixture.moment(0, 0, dayOffset: 3)
        let saved = TaskOwnership.saved(previous: decided, updated: edited)
        #expect(saved.rescheduleMode == nil)
        #expect(saved.isSetByUser(.day))

        // Поправил в карточке только название — Linea по-прежнему решает сама.
        var renamed = decided
        renamed.title = "Подготовить презентацию для клиента"
        #expect(TaskOwnership.saved(previous: decided, updated: renamed).rescheduleMode == .automatic)
        // «Позже сегодня» из меню — режим ставит само сохранение.
        let later = reschedule.apply(.laterToday, to: decided, context: context([decided]))
        #expect(TaskOwnership.saved(previous: decided, updated: later.task).rescheduleMode == .laterToday)
    }

    @Test("Задача, у которой окно наступило: «Время выбирает Linea» в карточке")
    func plannedAutomaticStatus() throws {
        let decided = reschedule.apply(.automatic, to: task(), context: context([task()])).task
        #expect(TaskExecutionText.status(of: decided, time: WowFixture.time(11, 30)) == "Время выбирает Linea")
        #expect(TaskExecutionText.caption(of: decided, time: WowFixture.time(11, 30)) == nil)
    }

    @Test("Задача, сохранённая до «Пусть Linea решит», читается: место выбирал человек")
    func oldTaskDecodes() throws {
        let json = """
        {"id":"\(id(1).uuidString)","title":"Отчёт","createdAt":800000000}
        """
        let decoded = try JSONDecoder().decode(LineaTask.self, from: Data(json.utf8))
        #expect(decoded.rescheduleMode == nil)
        var automatic = decoded
        automatic.rescheduleMode = .automatic
        let roundTrip = try JSONDecoder().decode(LineaTask.self, from: JSONEncoder().encode(automatic))
        #expect(roundTrip.rescheduleMode == .automatic)
    }
}
