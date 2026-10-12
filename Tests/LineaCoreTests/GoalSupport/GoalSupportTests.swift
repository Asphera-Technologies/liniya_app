import Testing
import Foundation
@testable import LineaCore

/// Мягкая поддержка целей: окно среди текущих дел (баланс дня) и возврат к
/// давно не двигавшейся цели. Время — среда 9 сентября 2026, 10:00 по Москве.
@Suite("Поддержка целей: баланс дня и возврат к цели")
struct GoalSupportTests {
    private let time = WowFixture.time(10, 0)
    private let profile = WowFixture.profile
    private let betaID = UUID(uuidString: "60D10000-0000-0000-0000-000000000001")!

    private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "60D20000-0000-0000-0000-%012d", n))! }

    private func goal(_ title: String = "Запустить Линия Beta", id: UUID? = nil, priority: TaskPriority = .important,
                      createdDaysAgo: Int = 10) -> LineaGoal {
        LineaGoal(id: id ?? betaID, title: title, createdAt: WowFixture.moment(9, dayOffset: -createdDaysAgo),
                  priority: priority)
    }

    private func task(_ n: Int, _ title: String, goalID: UUID? = nil, dayOffset: Int? = 0, done: Bool = false) -> LineaTask {
        LineaTask(id: id(n), title: title, date: dayOffset.map { WowFixture.moment(0, dayOffset: $0) }, isDone: done,
                  createdAt: WowFixture.created, goalID: goalID,
                  completedAt: done ? WowFixture.moment(9, dayOffset: dayOffset ?? 0) : nil)
    }

    /// Пример заказчика: обязательства и быт, ни одного шага к целям.
    private var busyDay: [LineaTask] {
        [
            task(1, "Отправить договор клиенту"),
            task(2, "Встреча с клиентом"),
            task(3, "Оплатить интернет"),
            task(4, "Купить продукты"),
            task(5, "Разобрать почту"),
        ]
    }

    private var meeting: Commitment {
        Commitment(id: "cal-1", title: "Планёрка", start: WowFixture.moment(11), end: WowFixture.moment(11, 30),
                   kind: .meeting, source: .calendar)
    }

    private func record(feedback: [UserFeedback] = [], blocks: [PlanBlock] = [], dayOffset: Int = 0) -> DayRecord {
        let day = WowFixture.moment(0, dayOffset: dayOffset)
        var snapshot = WowFixture.snapshot(at: time, commitments: [meeting])
        snapshot.tasks = []
        let plan = DayPlan(id: WowFixture.planID, day: time.startOfDay(day), createdAt: time.now,
                           snapshotID: WowFixture.snapshotID, blocks: blocks, topTaskIDs: [])
        return DayRecord(day: time.startOfDay(day), snapshot: snapshot, plan: plan, feedback: feedback, updatedAt: time.now)
    }

    private func balance(tasks: [LineaTask], goals: [LineaGoal], record: DayRecord? = nil) -> GoalOffer? {
        GoalBalance().offer(tasks: tasks, goals: goals, record: record ?? self.record(), profile: profile, time: time)
    }

    // MARK: Баланс дня

    @Test("Пример заказчика: много текущих дел, ни одного шага к цели — «Оставить 30 минут» / «Не сегодня»")
    func busyDayOffersWindow() throws {
        let offer = try #require(balance(tasks: busyDay, goals: [goal()]))
        #expect(offer.kind == .balance)
        #expect(offer.goalID == betaID)
        #expect(offer.observation == "Сегодня много текущих дел.")
        #expect(offer.question == "Хочешь оставить небольшое окно для цели «Запустить Линия Beta»?")
        #expect(offer.detail == "3 обязательства · 2 бытовых дела · 1 другое дело · 0 шагов к целям",
                "Встреча из календаря — тоже обязательство")
        #expect(offer.acceptTitle == "Оставить 30 минут")
        #expect(offer.declineTitle == "Не сегодня")
        #expect(offer.minutes == 30)
        #expect(offer.day == time.today)
    }

    @Test("«Не сегодня» — в этот день больше никаких увещеваний; согласие — тоже ответ")
    func answeredTodayIsQuiet() {
        for answer in [GoalOfferAnswer.Answer.declined, .accepted] {
            let answered = record().answering(GoalOfferAnswer(kind: .balance, goalID: betaID, answer: answer), at: time.now)
            #expect(balance(tasks: busyDay, goals: [goal()], record: answered) == nil)
        }
        // Ответ на возврат к цели — другой вопрос: баланс ещё может спросить.
        let other = record().answering(GoalOfferAnswer(kind: .returnAttention, goalID: betaID, answer: .declined), at: time.now)
        #expect(balance(tasks: busyDay, goals: [goal()], record: other) != nil)
        // Вчерашний ответ сегодня не действует, а запись вчерашнего дня — не сегодняшний день.
        let yesterday = record(dayOffset: -1)
        #expect(balance(tasks: busyDay, goals: [goal()], record: yesterday) == nil)
    }

    @Test("Шаг к важной цели сегодня есть, дел мало, цели неважные или на окно нет времени — молчит")
    func balancedDayIsQuiet() {
        let withStep = busyDay + [task(6, "Опубликовать сборку", goalID: betaID)]
        #expect(balance(tasks: withStep, goals: [goal()]) == nil)
        let doneStep = busyDay + [task(7, "Собрать отзывы", goalID: betaID, done: true)]
        #expect(balance(tasks: doneStep, goals: [goal()]) == nil, "Закрытый сегодня шаг — тоже шаг")
        #expect(balance(tasks: Array(busyDay.prefix(2)), goals: [goal()]) == nil, "2 дела и встреча — не много")
        #expect(balance(tasks: busyDay, goals: [goal(priority: .low)]) == nil)
        #expect(balance(tasks: busyDay, goals: []) == nil)

        let packed = PlanBlock(id: "full", kind: .focus, title: "Работа", start: time.now,
                               end: WowFixture.moment(21))
        #expect(balance(tasks: busyDay, goals: [goal()], record: record(blocks: [packed])) == nil, "Нет свободных 30 минут")
        let tight = PlanBlock(id: "tight", kind: .focus, title: "Работа", start: WowFixture.moment(10, 20),
                              end: WowFixture.moment(21))
        #expect(balance(tasks: busyDay, goals: [goal()], record: record(blocks: [tight])) == nil, "20 минут — мало")
    }

    @Test("Предлагает главную из важных целей: важнее — потом с ближним сроком")
    func offersMainGoal() throws {
        let normal = goal("Выучить испанский", id: id(50), priority: .normal)
        var urgent = goal("Сдать отчёт по проекту", id: id(51))
        urgent.endDate = WowFixture.moment(0, dayOffset: 3)
        let offer = try #require(balance(tasks: busyDay, goals: [normal, goal(), urgent]))
        #expect(offer.goalID == id(51))
    }

    @Test("Состав дня: задачи плана, на сегодня и закрытые сегодня; отменённые — нет")
    func dayComposition() {
        var cancelled = task(8, "Купить подарок")
        cancelled.cancelledAt = time.now
        let tomorrow = task(9, "Оплатить свет", dayOffset: 1)
        let inbox = task(10, "Позвонить маме", dayOffset: nil)
        let planned = PlanBlock(id: "p", kind: .focus, taskID: inbox.id, title: inbox.title,
                                start: WowFixture.moment(12), end: WowFixture.moment(12, 30))
        let composition = DayComposition.of(
            tasks: busyDay + [cancelled, tomorrow, inbox], plan: record(blocks: [planned]).plan,
            commitments: [meeting], importantGoalIDs: [betaID], time: time
        )
        #expect(composition.obligations == 3)
        #expect(composition.maintenance == 2)
        #expect(composition.other == 2, "«Позвонить маме» из «Без даты» план поставил сегодня")
        #expect(composition.goalSteps == 0)
        #expect(GoalSupportText.composition(DayComposition(obligations: 1, maintenance: 0, other: 0, goalSteps: 2))
                == "1 обязательство · 2 шага к целям")
    }

    // MARK: Окно для цели

    @Test("Окно — задача к цели на 30 минут; у цели команды — про свою часть")
    func windowTask() throws {
        let offer = try #require(balance(tasks: busyDay, goals: [goal()]))
        let window = GoalWindow.task(for: goal(), offer: offer, id: id(60), time: time)
        #expect(window.title == "Окно для цели «Запустить Линия Beta»")
        #expect(window.date == time.today)
        #expect(window.estimatedMinutes == 30)
        #expect(window.goalID == betaID)
        #expect(window.priority == .normal, "Окно — мягкая поддержка, обязательства дня оно не вытесняет")
        #expect(window.scheduledStart == nil, "Место найдёт план")
        #expect(window.userFields == [.day, .duration, .goal], "Человек согласился — это его поля")

        var company = goal("Довести выручку компании до 5 млн ₽ в месяц")
        company.scope = .company
        company.ownerScope = "Новые enterprise-клиенты и ключевые переговоры"
        #expect(GoalWindow.task(for: company, offer: offer, id: id(61), time: time).title
                == "Окно для своей части: Новые enterprise-клиенты и ключевые переговоры")
        #expect(GoalSupportText.balanceAccepted(offer, plannedAt: WowFixture.moment(16, 30), time: time)
                == "Оставила 30 минут для цели «Запустить Линия Beta» — сегодня в 16:30.")
        #expect(GoalSupportText.balanceAccepted(offer, plannedAt: nil, time: time)
                == "Оставила 30 минут для цели «Запустить Линия Beta» — время найдёт план.")
    }

    // MARK: Возврат к цели

    private func attention(goals: [LineaGoal], tasks: [LineaTask] = [], record: DayRecord? = nil) -> GoalOffer? {
        GoalAttention().offer(goals: goals, tasks: tasks, record: record, time: time)
    }

    @Test("Пример заказчика: четыре дня без действий — «Хочешь найти для неё небольшое окно завтра?»")
    func idleGoalOffer() throws {
        let lastStep = task(20, "Опубликовать сборку", goalID: betaID, dayOffset: -4, done: true)
        let offer = try #require(attention(goals: [goal()], tasks: [lastStep]))
        #expect(offer.kind == .returnAttention)
        #expect(offer.observation == "По цели «Запустить Линия Beta» не было действий четыре дня.")
        #expect(offer.question == "Хочешь найти для неё небольшое окно завтра?")
        #expect(offer.acceptTitle == "Да")
        #expect(offer.declineTitle == "Пока нет")
        #expect(offer.day == time.adding(days: 1, to: time.today))
        #expect(!offer.observation.contains("отста"), "Не «ты отстаёшь»")
        #expect(GoalSupportText.returnAccepted(offer) == "Хорошо: завтра Linea найдёт для неё 30 минут.")
    }

    @Test("Не напоминает: действия недавно, цель недавно пересматривали, окно уже есть, неважная цель")
    func attentionIsQuiet() {
        let recent = task(21, "Собрать отзывы", goalID: betaID, dayOffset: -3, done: true)
        #expect(attention(goals: [goal()], tasks: [recent]) == nil, "Три дня — ещё не давно")
        #expect(attention(goals: [goal(createdDaysAgo: 2)]) == nil, "Цель создана два дня назад")

        var reviewed = goal()
        reviewed.lastReviewedAt = WowFixture.moment(18, dayOffset: -1)
        #expect(attention(goals: [reviewed]) == nil, "Вчера пересматривал — думал о ней")

        let tomorrow = task(22, "Окно для цели", goalID: betaID, dayOffset: 1)
        #expect(attention(goals: [goal()], tasks: [tomorrow]) == nil, "Окно на завтра уже есть")
        var started = task(23, "Написать пост", goalID: betaID, dayOffset: nil)
        started.startedAt = WowFixture.moment(9, dayOffset: -5)
        #expect(attention(goals: [goal()], tasks: [started]) == nil, "Задача цели в работе")

        #expect(attention(goals: [goal(priority: .low)]) == nil)
        var done = goal()
        done.isCompleted = true
        #expect(attention(goals: [done]) == nil)
    }

    @Test("«Пока нет» — неделю не напоминает; один такой вопрос в день")
    func notYetBacksOff() {
        var snoozed = goal()
        snoozed.attentionSnoozedUntil = GoalAttention.snoozed(until: time)
        #expect(snoozed.attentionSnoozedUntil == time.adding(days: 7, to: time.now))
        #expect(attention(goals: [snoozed]) == nil)
        snoozed.attentionSnoozedUntil = WowFixture.moment(9)
        #expect(attention(goals: [snoozed]) != nil, "Неделя прошла — можно спросить снова")

        let answered = record().answering(GoalOfferAnswer(kind: .returnAttention, goalID: id(70), answer: .declined), at: time.now)
        #expect(attention(goals: [goal()], record: answered) == nil, "Сегодня уже спрашивали")
    }

    @Test("Из нескольких давно стоящих — важная, потом та, что дольше без движения")
    func picksMostImportantIdleGoal() {
        let older = goal("Выучить испанский", id: id(80), priority: .normal, createdDaysAgo: 30)
        let important = goal("Запустить Линия Beta", createdDaysAgo: 6)
        #expect(attention(goals: [older, important])?.goalID == betaID)
        let sameLevel = goal("Пробежать полумарафон", id: id(81), priority: .normal, createdDaysAgo: 12)
        #expect(attention(goals: [sameLevel, older])?.goalID == id(80))
        #expect(attention(goals: [older])?.observation == "По цели «Выучить испанский» не было действий больше месяца.")
    }

    @Test("Дни словами: «четыре дня», «неделю», «две недели», «12 дней», «больше месяца»")
    func idleWords() {
        #expect(GoalSupportText.idle(days: 4) == "четыре дня")
        #expect(GoalSupportText.idle(days: 5) == "пять дней")
        #expect(GoalSupportText.idle(days: 7) == "неделю")
        #expect(GoalSupportText.idle(days: 14) == "две недели")
        #expect(GoalSupportText.idle(days: 12) == "12 дней")
        #expect(GoalSupportText.idle(days: 22) == "22 дня")
        #expect(GoalSupportText.idle(days: 45) == "больше месяца")
    }

    @Test("Ответ пишется в день и читается обратно")
    func answerIsRecorded() throws {
        let answer = GoalOfferAnswer(kind: .balance, goalID: betaID, answer: .accepted, taskID: id(90))
        let answered = record().answering(answer, at: time.now)
        #expect(answered.goalOfferAnswers == [answer])
        #expect(answered.feedback.count == 1)
        let decoded = try JSONDecoder().decode(DayRecord.self, from: JSONEncoder().encode(answered))
        #expect(decoded.goalOfferAnswers == [answer])
    }
}
