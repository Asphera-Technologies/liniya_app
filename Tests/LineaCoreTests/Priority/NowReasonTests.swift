import Testing
import Foundation
@testable import LineaCore

/// Причина у «Сейчас»: у каждой рекомендации — одна короткая фраза, понятная
/// без техники. Среда 9 сентября 2026, рабочий день 9:00–21:00 по Москве.
@Suite("Сейчас: почему это")
struct NowReasonTests {
    private let useCase = NextActionUseCase(renderer: RuleBasedExplainer())

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "58000000-0000-0000-0000-%012d", n))!
    }

    private func task(
        _ n: Int, _ title: String, date: Date? = WowFixture.today, priority: TaskPriority = .normal,
        deadline: Date? = nil, start: Date? = nil, minutes: Int = 30, demand: CognitiveDemand = .normal,
        goal: UUID? = nil, deferrals: Int = 0, blockedBy: [UUID] = []
    ) -> LineaTask {
        LineaTask(id: id(n), title: title, date: date, priority: priority,
                  createdAt: WowFixture.created.addingTimeInterval(TimeInterval(n * 60)),
                  deadline: deadline, scheduledStart: start, estimatedMinutes: minutes, cognitiveDemand: demand,
                  goalID: goal, deferralCount: deferrals, blockedBy: blockedBy)
    }

    private static var meeting: Commitment {
        Commitment(id: "meeting", title: "Встреча с клиентом", start: WowFixture.moment(15, 50),
                   end: WowFixture.moment(16, 20), kind: .meeting, source: .calendar)
    }

    private static let betaID = UUID(uuidString: "59000000-0000-0000-0000-000000000001")!
    private static let spanishID = UUID(uuidString: "59000000-0000-0000-0000-000000000002")!

    /// Главная цель — важная; вторая — средняя.
    private static var goals: [LineaGoal] {
        [
            LineaGoal(id: betaID, title: "Запустить Линия Beta", createdAt: WowFixture.created, priority: .important),
            LineaGoal(id: spanishID, title: "Выучить испанский", createdAt: WowFixture.created, priority: .normal),
        ]
    }

    private func run(
        at time: TimeContext, tasks: [LineaTask], commitments: [Commitment] = [], goals: [LineaGoal] = [],
        energy: Double = 0.6, plan: DayPlan? = nil, preferred: UUID? = nil
    ) -> NextAction? {
        let state = PlanFixture.state(energy: energy, confidence: 0.9, advice: .normal, at: time)
        let record = DayRecord(day: WowFixture.today,
                               snapshot: PlanFixture.snapshot(tasks: tasks, commitments: commitments, goals: goals, at: time),
                               state: state, plan: plan, updatedAt: time.now)
        return useCase.run(record: record, tasks: tasks, calibration: .default, time: time, preferred: preferred)
    }

    private func reason(
        at time: TimeContext = WowFixture.time(10), _ tasks: [LineaTask], commitments: [Commitment] = [],
        goals: [LineaGoal] = [], energy: Double = 0.6, plan: DayPlan? = nil
    ) -> String? {
        run(at: time, tasks: tasks, commitments: commitments, goals: goals, energy: energy, plan: plan)?.reason
    }

    // MARK: Примеры заказчика

    @Test("«До встречи 35 мин — на эту задачу как раз хватит.»")
    func windowExample() throws {
        let action = try #require(run(at: WowFixture.time(15, 15), tasks: [task(1, "Ответить на письма", minutes: 15)],
                                      commitments: [Self.meeting]))
        #expect(action.option?.title == "Ответить на письма")
        #expect(action.reason == "До встречи 35 мин — на эту задачу как раз хватит.")
    }

    @Test("«Высокий приоритет, а срок — сегодня вечером.»")
    func deadlineExample() {
        let offer = task(1, "Отправить КП клиенту", priority: .important, deadline: WowFixture.moment(19), minutes: 60)
        #expect(reason([offer]) == "Высокий приоритет, а срок — сегодня вечером.")
    }

    @Test("«Это ближайший шаг по твоей главной цели.»")
    func mainGoalExample() {
        let build = task(1, "Опубликовать сборку в TestFlight", goal: Self.betaID)
        #expect(reason([build], goals: Self.goals) == "Это ближайший шаг по твоей главной цели.")
        // Не главная цель — называется по имени.
        let lesson = task(2, "Урок испанского", goal: Self.spanishID)
        #expect(reason([lesson], goals: Self.goals) == "Это шаг к цели «Выучить испанский».")
    }

    // MARK: Остальные причины

    @Test("Срок: прошёл, сегодня до часа, завтра; день задачи прошёл")
    func deadlines() {
        let late = task(1, "Сдать отчёт", deadline: WowFixture.moment(18, 0, dayOffset: -1))
        #expect(reason([late]) == "Срок уже прошёл — лучше закрыть сейчас.")
        let yesterday = task(2, "Оплатить свет", date: WowFixture.calendar.startOfDay(for: WowFixture.moment(12, 0, dayOffset: -1)))
        #expect(reason([yesterday]) == "Её день уже прошёл — лучше закрыть сейчас.")
        let afternoon = task(3, "Отправить договор", priority: .important, deadline: WowFixture.moment(15))
        #expect(reason([afternoon]) == "Высокий приоритет, а срок — сегодня до 15:00.")
        let morning = task(4, "Подписать акт", date: nil, deadline: WowFixture.moment(12, 0, dayOffset: 1))
        #expect(reason([morning]) == "Срок — завтра до 12:00.")
        let tomorrow = task(5, "Собрать отчёт", date: nil, deadline: WowFixture.moment(21, 0, dayOffset: 1))
        #expect(reason([tomorrow]) == "Срок — завтра.")
        // Срок через неделю — ещё не причина.
        let far = task(6, "Продлить страховку", priority: .important, deadline: WowFixture.moment(21, 0, dayOffset: 7))
        #expect(reason([far]) == "Высокий приоритет — лучше не откладывать.")
    }

    @Test("Своё время, принятый план, тесное окно до конца дня")
    func timeAndPlan() {
        let call = task(1, "Позвонить в банк", start: WowFixture.moment(10, 5), minutes: 15)
        #expect(reason([call]) == "Назначена на 10:05.")

        let mail = task(2, "Разобрать почту")
        let block = PlanBlock(id: "b", kind: .focus, taskID: mail.id, title: mail.title,
                              start: WowFixture.moment(9, 50), end: WowFixture.moment(10, 20))
        let plan = DayPlan(id: WowFixture.planID, day: WowFixture.today, status: .accepted, createdAt: WowFixture.morning.now,
                           snapshotID: WowFixture.snapshotID, blocks: [block], topTaskIDs: [mail.id])
        #expect(reason([mail], plan: plan) == "Сейчас её время по плану.")

        let review = task(3, "Проверить отчёт", minutes: 40)
        #expect(reason(at: WowFixture.time(20, 10), [review]) == "До конца рабочего дня 50 мин — на эту задачу как раз хватит.")
    }

    @Test("Ждут другие, откладывали, силы на сложное, без даты, короткая, просто важное")
    func lesserReasons() {
        let data = task(1, "Собрать данные", minutes: 45)
        let report = task(2, "Написать отчёт", minutes: 45, blockedBy: [id(1)])
        #expect(reason([data, report]) == "Без неё не начать «Написать отчёт».")
        let slides = task(3, "Сделать слайды", minutes: 45, blockedBy: [id(1)])
        #expect(reason([data, report, slides]) == "Без неё не начать ещё 2 задачи.")

        #expect(reason([task(4, "Записаться к врачу", minutes: 45, deferrals: 3)]) == "Её откладывали уже 3 раза — пора закрыть.")
        #expect(reason(at: WowFixture.time(11), [task(5, "Разработать архитектуру", minutes: 90, demand: .deep)], energy: 0.9)
                == "Сейчас хорошее время для сложной задачи.")
        #expect(reason([task(6, "Посмотреть новые AI-модели", date: nil, minutes: 45)]) == "У неё нет даты, а свободное время есть сейчас.")
        #expect(reason([task(7, "Купить батарейки", minutes: 10)]) == "Короткая — можно закрыть сразу.")
        #expect(reason([task(8, "Обновить резюме", minutes: 45)]) == "Самое важное из того, что можно сделать сейчас.")
    }

    @Test("Причина считается и для выбранного в «Другое»")
    func preferredHasItsOwnReason() throws {
        let tasks = [
            task(1, "Отправить КП клиенту", priority: .important, deadline: WowFixture.moment(19), minutes: 60),
            task(2, "Купить батарейки", minutes: 10),
        ]
        let first = try #require(run(at: WowFixture.time(10), tasks: tasks))
        #expect(first.taskID == id(1))
        let chosen = try #require(run(at: WowFixture.time(10), tasks: tasks, preferred: id(2)))
        #expect(chosen.taskID == id(2))
        #expect(chosen.reason == "Короткая — можно закрыть сразу.")
    }

    @Test("Главная цель — самая важная, при равной важности — с ближним сроком")
    func mainGoal() {
        var goals = Self.goals
        #expect(NowReasoner.mainGoal(in: goals)?.id == Self.betaID)
        goals[0].priority = .normal
        goals[1].endDate = WowFixture.moment(0, 0, dayOffset: 10)
        #expect(NowReasoner.mainGoal(in: goals)?.id == Self.spanishID)
        goals[1].isCompleted = true
        #expect(NowReasoner.mainGoal(in: goals)?.id == Self.betaID)
        #expect(NowReasoner.mainGoal(in: []) == nil)
    }

    // MARK: Одно короткое предложение, без техники

    @Test("У каждой рекомендации весь день — причина: одно короткое предложение без баллов и уверенностей")
    func everyRecommendationHasAShortHumanReason() throws {
        let tasks = [
            task(1, "Отправить КП клиенту", priority: .important, deadline: WowFixture.moment(19), minutes: 60),
            task(2, "Опубликовать сборку в TestFlight", goal: Self.betaID),
            task(3, "Ответить на письма", minutes: 15),
            task(4, "Подготовить стратегию", priority: .important, minutes: 90, demand: .deep),
            task(5, "Купить батарейки", date: nil, minutes: 10),
            task(6, "Собрать данные", minutes: 45),
            task(7, "Написать отчёт", minutes: 45, blockedBy: [id(6)]),
            task(8, "Позвонить в банк", start: WowFixture.moment(17, 30), minutes: 15),
        ]
        let validator = ExplanationValidator()
        let forbidden = ["балл", "score", "%", "уверенн", "confidence", "вероятн", "оценк", "importance", "action"]
        var seen = 0
        var moment = WowFixture.moment(9)
        while moment < WowFixture.moment(21) {
            let time = TimeContext(now: moment, timeZoneIdentifier: WowFixture.timeZoneID)
            let snapshot = PlanFixture.snapshot(tasks: tasks, commitments: [Self.meeting], goals: Self.goals, at: time)
            let record = DayRecord(day: WowFixture.today, snapshot: snapshot,
                                   state: PlanFixture.state(energy: 0.6, confidence: 0.9, advice: .normal, at: time),
                                   updatedAt: time.now)
            if let action = useCase.run(record: record, tasks: tasks, calibration: .default, time: time), action.option != nil {
                seen += 1
                let reason = action.reason
                #expect(!reason.isEmpty, "Без причины в \(PlanFixture.hhmm(moment, time: time))")
                #expect(reason.hasSuffix("."), "\(reason)")
                #expect(ExplanationValidator.sentenceCount(Self.unquoted(reason)) == 1, "Одно предложение: \(reason)")
                #expect(Self.unquoted(reason).count <= 80, "Коротко: \(reason)")
                #expect(!forbidden.contains { reason.lowercased().contains($0) }, "Без техники: \(reason)")
                let allowed = validator.allowedNumbers(facts: action.facts, time: time)
                #expect(ExplanationValidator.numericTokens(in: Self.unquoted(reason)).isSubset(of: allowed), "Числа только из фактов: \(reason)")
            }
            moment = moment.addingTimeInterval(15 * 60)
        }
        #expect(seen > 30, "Рекомендаций за день: \(seen)")
    }

    /// Названия задач и целей в «» — слова человека: в них могут быть точки и числа.
    private static func unquoted(_ text: String) -> String {
        var result = ""
        var depth = 0
        for character in text {
            if character == "«" { depth += 1; result.append("…"); continue }
            if character == "»" { depth = max(0, depth - 1); continue }
            if depth == 0 { result.append(character) }
        }
        return result
    }
}
