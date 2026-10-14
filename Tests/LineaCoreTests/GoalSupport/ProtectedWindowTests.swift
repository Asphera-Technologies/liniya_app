import Testing
import Foundation
@testable import LineaCore

/// Защищённое окно под цель: если человек разрешил, Linea каждый день
/// оставляет в плане время для цели. Не событие календаря: окно весит больше
/// обычных задач, но срочная задача или встреча его передвигают. Среда
/// 9 сентября 2026, Москва, рабочий день 9–21.
@Suite("Защищённое окно под цель")
struct ProtectedWindowTests {
    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "E0000000-0000-0000-0000-%012d", n))!
    }

    private var beta: LineaGoal {
        LineaGoal(id: id(100), title: "Linea Beta", createdAt: WowFixture.created, priority: .important,
                  protectedWindow: GoalWindowPolicy(minutes: 30, partOfDay: .evening))
    }

    private func meeting(_ hour: Int, _ minute: Int = 0, until endHour: Int, _ endMinute: Int = 0, dayOffset: Int = 0) -> Commitment {
        Commitment(id: "event-\(dayOffset)-\(hour)\(minute)", title: "Встреча", start: WowFixture.moment(hour, minute, dayOffset: dayOffset),
                   end: WowFixture.moment(endHour, endMinute, dayOffset: dayOffset), kind: .meeting, source: .calendar)
    }

    private func task(_ n: Int, _ title: String, minutes: Int, deadline: Date? = nil, goal: UUID? = nil, dayOffset: Int = 0) -> LineaTask {
        LineaTask(id: id(n), title: title, date: WowFixture.moment(0, 0, dayOffset: dayOffset), createdAt: WowFixture.created,
                  deadline: deadline, estimatedMinutes: minutes, goalID: goal)
    }

    private func plan(_ tasks: [LineaTask], goals: [LineaGoal], commitments: [Commitment] = [],
                      at time: TimeContext = WowFixture.time(10)) -> DayPlan {
        PlanFixture.engine(rules: []).plan(
            snapshot: PlanFixture.snapshot(tasks: tasks, commitments: commitments, goals: goals, at: time),
            state: PlanFixture.state(energy: 0.7, confidence: 0.9, advice: .normal, at: time),
            time: time, planID: WowFixture.planID
        )
    }

    private func goalBlocks(_ plan: DayPlan) -> [String] {
        plan.blocks.filter { $0.kind == .goal }.map { "\(PlanFixture.hhmm($0.start))–\(PlanFixture.hhmm($0.end)) \($0.title)" }
    }

    @Test("Пример заказчика: «17:30–18:00 Продвинуть «Linea Beta»» — в плане, не в календаре")
    func customerExample() throws {
        let day = plan([task(1, "Ответить клиенту", minutes: 15)], goals: [beta], commitments: [meeting(17, until: 17, 30)])
        #expect(goalBlocks(day) == ["17:30–18:00 Продвинуть «Linea Beta»"])
        let block = try #require(day.blocks.first { $0.kind == .goal })
        #expect(block.goalID == beta.id)
        #expect(block.taskID == nil, "Не задача")
        #expect(PlanFixture.overlaps(day.blocks) == false)
        #expect(GoalWindowPolicy(minutes: 30, partOfDay: .evening).summary == "30 мин · вечером")
        #expect(GoalWindowPolicy(minutes: 60, partOfDay: .any, weekdaysOnly: true).summary == "1 ч · когда свободно · по будням")
    }

    @Test("Повышенный вес: обычные задачи окно не занимают, даже если дня на всё не хватает")
    func outweighsOrdinaryTasks() {
        let many = (1...14).map { task($0, "Дело \($0)", minutes: 60) }
        let day = plan(many, goals: [beta])
        #expect(goalBlocks(day) == ["17:00–17:30 Продвинуть «Linea Beta»"])
        #expect(!day.deferredTaskIDs.isEmpty, "Обычные дела не влезли — окно всё равно осталось")
        #expect(PlanFixture.overlaps(day.blocks) == false)
    }

    @Test("Срочная задача сильнее окна: окно переезжает; места нет совсем — сегодня окна нет")
    func urgentTaskMovesWindow() {
        // Вечер занят встречами, кроме 18:00–19:30; срочная задача на полтора часа со сроком сегодня.
        let evening = [meeting(17, until: 18), meeting(19, 30, until: 21)]
        let urgent = task(1, "Сдать отчёт", minutes: 90, deadline: WowFixture.moment(20))
        let busyDay = [meeting(10, until: 17)]
        let day = plan([urgent], goals: [beta], commitments: busyDay + evening)
        #expect(day.blocks.contains { $0.taskID == urgent.id }, "Срочное — в плане")
        #expect(goalBlocks(day).isEmpty, "Свободное время ушло на срочное — сегодня без окна")

        // Без срочного то же окно 18:00–18:30 — окну.
        #expect(goalBlocks(plan([], goals: [beta], commitments: busyDay + evening)) == ["18:00–18:30 Продвинуть «Linea Beta»"])
    }

    @Test("Встреча в выбранное время — окно переезжает в свободное, а не исчезает")
    func eventMovesWindow() {
        #expect(goalBlocks(plan([], goals: [beta], commitments: [meeting(17, until: 19)])) == ["19:00–19:30 Продвинуть «Linea Beta»"])
        // Вечер занят целиком — окно в другое время дня.
        #expect(goalBlocks(plan([], goals: [beta], commitments: [meeting(17, until: 21)])) == ["10:00–10:30 Продвинуть «Linea Beta»"])
    }

    @Test("Окна нет, если не разрешали, цель не активна, сегодня выходной при «по будням» или окно уже взято в работу")
    func whenNoWindow() {
        var off = beta
        off.protectedWindow = nil
        #expect(goalBlocks(plan([], goals: [off])).isEmpty)
        var inactive = beta
        inactive.isActive = false
        #expect(goalBlocks(plan([], goals: [inactive])).isEmpty)
        var weekdays = beta
        weekdays.protectedWindow = GoalWindowPolicy(minutes: 30, partOfDay: .evening, weekdaysOnly: true)
        let saturday = WowFixture.time(10, 0, dayOffset: 3)
        let weekend = PlanFixture.engine(rules: []).plan(
            snapshot: ContextSnapshot(id: WowFixture.snapshotID, day: saturday.today, capturedAt: saturday.now,
                                      timeZoneIdentifier: WowFixture.timeZoneID, signals: [], providerStatuses: [:],
                                      tasks: [], goals: [weekdays], commitments: [], profile: WowFixture.profile,
                                      nutrition: nil, meals: []),
            state: PlanFixture.state(energy: 0.7, confidence: 0.9, advice: .normal, at: saturday),
            time: saturday, planID: WowFixture.planID
        )
        #expect(goalBlocks(weekend).isEmpty, "Суббота — окна по будням нет")

        let time = WowFixture.time(10)
        let taken = GoalWindow.protectedTask(for: beta, title: "Продвинуть «Linea Beta»", minutes: 30, time: time)
        #expect(goalBlocks(plan([taken], goals: [beta])).isEmpty, "Окно сегодня уже взято в работу")
    }

    @Test("Задача окна: одна на цель и день")
    func protectedTaskID() {
        let time = WowFixture.time(10)
        let today = GoalWindow.protectedTaskID(goalID: beta.id, day: time.today, time: time)
        #expect(today == GoalWindow.protectedTaskID(goalID: beta.id, day: WowFixture.moment(18), time: time))
        #expect(today != GoalWindow.protectedTaskID(goalID: beta.id, day: time.adding(days: 1, to: time.today), time: time))
        let task = GoalWindow.protectedTask(for: beta, title: "Продвинуть «Linea Beta»", minutes: 25, time: time)
        #expect(task.id == today)
        #expect(task.goalID == beta.id)
        #expect(task.estimatedMinutes == 25)
        #expect(task.date == time.today)
    }

    // MARK: «Сейчас»

    private func record(_ tasks: [LineaTask], at time: TimeContext) -> DayRecord {
        let snapshot = PlanFixture.snapshot(tasks: tasks, commitments: [], goals: [beta], at: time)
        let state = PlanFixture.state(energy: 0.7, confidence: 0.9, advice: .normal, at: time)
        let day = PlanFixture.engine(rules: []).plan(snapshot: snapshot, state: state, time: time, planID: WowFixture.planID)
        return DayRecord(day: WowFixture.today, snapshot: snapshot, state: state, plan: day, updatedAt: time.now)
    }

    @Test("Во время окна «Сейчас» — само окно, если задач цели нет; «Начать» создаст задачу")
    func nowIsTheWindow() throws {
        let time = WowFixture.time(17, 5)
        let tasks = [task(1, "Оплатить интернет", minutes: 10)]
        let now = try #require(NextActionUseCase(renderer: RuleBasedExplainer())
            .run(record: record(tasks, at: time), tasks: tasks, calibration: .default, time: time))
        let option = try #require(now.option)
        #expect(option.title == "Продвинуть «Linea Beta»")
        #expect(option.windowGoalID == beta.id)
        #expect(option.taskID == GoalWindow.protectedTaskID(goalID: beta.id, day: time.today, time: time))
        #expect(option.minutes == 30)
        #expect(now.reason == "Сейчас время для цели «Linea Beta» — до 17:35.")
        #expect(now.alternatives.map(\.title) == ["Оплатить интернет"], "Другое — как обычно")
    }

    @Test("Во время окна — сначала задачи этой цели; «Не сейчас» на окне — сегодня его больше не предлагать")
    func windowPrefersGoalTasks() throws {
        let time = WowFixture.time(17, 5)
        let tasks = [task(1, "Оплатить интернет", minutes: 10), task(2, "Собрать сборку", minutes: 30, goal: beta.id)]
        let useCase = NextActionUseCase(renderer: RuleBasedExplainer())
        let day = record(tasks, at: time)
        let now = try #require(useCase.run(record: day, tasks: tasks, calibration: .default, time: time))
        #expect(now.taskID == tasks[1].id)
        #expect(now.reason == "Сейчас время для цели «Linea Beta» — до 17:35.")

        let declined = day.appendingFeedback(.goalWindowDeclined(goalID: beta.id), at: time.now)
        let after = try #require(useCase.run(record: declined, tasks: [tasks[0]], calibration: .default, time: time))
        #expect(after.option?.windowGoalID == nil, "Окно больше не предлагается")
        #expect(after.taskID == tasks[0].id)
    }

    @Test("Цель с окном и план без него читаются из старых записей")
    func legacyDecode() throws {
        let goal = try JSONDecoder().decode(LineaGoal.self, from: JSONEncoder().encode(beta))
        #expect(goal.protectedWindow == GoalWindowPolicy(minutes: 30, partOfDay: .evening))
        let old = #"{"id":"\#(id(1).uuidString)","title":"Бег","progress":0,"isCompleted":false,"createdAt":800000000}"#
        #expect(try JSONDecoder().decode(LineaGoal.self, from: Data(old.utf8)).protectedWindow == nil)
        let block = #"{"id":"b","kind":"focus","title":"Отчёт","start":800000000,"end":800003600,"isTop":false,"isPinned":false,"facts":[]}"#
        #expect(try JSONDecoder().decode(PlanBlock.self, from: Data(block.utf8)).goalID == nil)
    }
}
