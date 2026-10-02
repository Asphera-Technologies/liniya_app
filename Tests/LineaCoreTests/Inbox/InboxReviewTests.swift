import Testing
import Foundation
@testable import LineaCore

/// «Без даты»: что лежит во входящих, когда Linea предлагает разбор, что
/// подсказывает и как сама ставит такие задачи в день. Время — среда
/// 9 сентября 2026, 08:00 по Москве.
@Suite("Без даты: входящие")
struct InboxReviewTests {
    private let time = WowFixture.morning
    private let review = InboxReview()

    private func task(
        _ number: Int,
        _ title: String,
        priority: TaskPriority = .normal,
        daysAgo: Int = 0,
        date: Date? = nil,
        deadline: Date? = nil,
        goalID: UUID? = nil,
        minutes: Int? = 30
    ) -> LineaTask {
        LineaTask(
            id: UUID(uuidString: String(format: "61000000-0000-0000-0000-%012d", number))!,
            title: title, date: date, priority: priority,
            createdAt: time.now.addingTimeInterval(TimeInterval(-daysAgo * 86_400 + number)),
            deadline: deadline, estimatedMinutes: minutes, goalID: goalID
        )
    }

    // MARK: Что во входящих

    @Test("Во «Без даты» — открытая задача без дня, срока и своего времени; давние — первыми")
    func membership() {
        let models = task(1, "Посмотреть новые AI-модели")
        let older = task(2, "Изучить новый API", daysAgo: 2)
        let dated = task(3, "Отчёт", date: WowFixture.today)
        let due = task(4, "Релиз", deadline: WowFixture.moment(18))
        var done = task(5, "Написать Саше")
        done.isDone = true

        #expect(InboxReview.isInInbox(models))
        #expect(!InboxReview.isInInbox(dated))
        #expect(!InboxReview.isInInbox(due))
        #expect(!InboxReview.isInInbox(done))
        #expect(InboxReview.inbox([models, dated, due, done, older]).map(\.title) == ["Изучить новый API", "Посмотреть новые AI-модели"])
    }

    // MARK: Когда предлагать разбор

    @Test("Разбор предлагается с трёх неразобранных или когда одна лежит три дня")
    func offer() {
        let two = [task(1, "Посмотреть новые AI-модели"), task(2, "Написать Саше")]
        #expect(review.offer(tasks: two, time: time) == nil)

        let three = two + [task(3, "Изучить новый API")]
        #expect(review.offer(tasks: three, time: time) == InboxReview.Offer(count: 3, text: "3 задачи без даты — разберём за минуту?"))

        let five = three + [task(4, "Разобрать фото"), task(5, "Купить лампу")]
        #expect(review.offer(tasks: five, time: time)?.text == "5 задач без даты — разберём за минуту?")

        let stale = [task(6, "Разобрать фото", daysAgo: 4)]
        #expect(review.offer(tasks: stale, time: time)?.text == "1 задача без даты — разберём за минуту?")
        #expect(review.offer(tasks: [task(7, "Разобрать фото", daysAgo: 2)], time: time) == nil)
    }

    @Test("Оставленные при разборе без даты лежат во входящих, но разбор больше не предлагают")
    func keptTasksAreQuiet() {
        let three = [task(1, "Посмотреть новые AI-модели"), task(2, "Написать Саше"), task(3, "Изучить новый API")]
        let kept = three.map { review.apply(.keep, to: $0, profile: WowFixture.profile, time: time) }
        #expect(InboxReview.inbox(kept).count == 3)
        #expect(InboxReview.unsorted(kept).isEmpty)
        #expect(review.offer(tasks: kept, time: time) == nil)
        // Новая задача — снова неразобранная, но одной мало.
        #expect(review.offer(tasks: kept + [task(4, "Купить лампу")], time: time) == nil)
    }

    // MARK: Подсказка

    @Test("Подсказка: куда задачу и почему")
    func suggestions() {
        func suggest(_ task: LineaTask, planned: Date? = nil) -> InboxReview.Suggestion {
            review.suggestion(for: task, goals: WowFixture.goals, plannedStart: planned, time: time)
        }
        #expect(suggest(task(1, "Посмотреть новые AI-модели"), planned: WowFixture.moment(16, 30))
            == .init(choice: .today, reason: "Сегодня в 16:30 есть свободное время — я уже поставила её туда."))
        #expect(suggest(task(2, "Подготовить релиз", goalID: WowFixture.goalMVP))
            == .init(choice: .thisWeek, reason: "Шаг к цели «Запустить MVP Linea» — лучше на этой неделе."))
        #expect(suggest(task(3, "Купить подарок", priority: .important))
            == .init(choice: .tomorrow, reason: "Важная — лучше не откладывать надолго."))
        #expect(suggest(task(4, "Книгу почитать", priority: .low))
            == .init(choice: .keep, reason: "Не срочная — может полежать без даты."))
        #expect(suggest(task(5, "Ответить Ивану"))
            == .init(choice: .tomorrow, reason: "Ответы лучше не держать долго."))
        #expect(suggest(task(6, "Отправить договор"))
            == .init(choice: .thisWeek, reason: "Обязательство — на этой неделе, день подберёт план."))
        #expect(suggest(task(7, "Посмотреть новые AI-модели"))
            == .init(choice: .thisWeek, reason: "На этой неделе — день подберёт план."))
        #expect(InboxReview.plannedCaption(WowFixture.moment(16, 30), time: time) == "Linea нашла время: сегодня в 16:30")
    }

    // MARK: Выбор

    @Test("Выбор при разборе: день и срок как в быстром вводе, задача помечена разобранной")
    func apply() {
        let base = task(1, "Посмотреть новые AI-модели")
        let profile = WowFixture.profile

        let today = review.apply(.today, to: base, profile: profile, time: time)
        #expect(today.date == WowFixture.today)
        #expect(today.deadline == nil)
        #expect(today.inboxReviewedAt == time.now)

        let tomorrow = review.apply(.tomorrow, to: base, profile: profile, time: time)
        #expect(tomorrow.date == time.adding(days: 1, to: WowFixture.today))

        let week = review.apply(.thisWeek, to: base, profile: profile, time: time)
        #expect(week.date == nil)
        #expect(week.deadline == TaskDay.endOfWeek(time: time, profile: profile))
        #expect(!InboxReview.isInInbox(week))

        let kept = review.apply(.keep, to: base, profile: profile, time: time)
        #expect(InboxReview.isInInbox(kept))
        #expect(kept.inboxReviewedAt == time.now)
        #expect(kept.title == base.title)
    }

    // MARK: Место в дне

    @Test("Linea сама ставит пару задач «Без даты» в свободное время — после задач дня, а не вместо них")
    func planPlacesInboxTasks() {
        let inbox = [
            task(1, "Посмотреть новые AI-модели"),
            task(2, "Изучить новый API"),
            task(3, "Разобрать фото"),
            task(4, "Книгу почитать", priority: .low),
        ]
        let engine = PlanFixture.engine()
        let state = PlanFixture.reducedState(at: time)
        let base = engine.plan(snapshot: WowFixture.snapshot(at: time), state: state, time: time, planID: WowFixture.planID)
        let plan = engine.plan(snapshot: PlanFixture.snapshot(tasks: WowFixture.tasks + inbox, at: time),
                               state: state, time: time, planID: WowFixture.planID)

        // Задачи дня стоят там же, где и без входящих, и «три главных» — те же.
        for block in base.blocks {
            #expect(plan.blocks.contains(block), "\(block.title) сдвинулась")
        }
        #expect(plan.topTaskIDs == base.topTaskIDs)

        let inboxIDs = Set(inbox.map(\.id))
        let placed = plan.focusBlocks.filter { $0.taskID.map(inboxIDs.contains) ?? false }
        #expect(placed.count == PriorityEngine.maxInboxPicks)
        #expect(!placed.contains { $0.taskID == inbox[3].id }, "«Не срочная» не ставится")
        #expect(PlanFixture.overlaps(plan.blocks) == false)
        // Не поместились — не перенос: дня у них не было.
        #expect(plan.deferredTaskIDs.allSatisfy { !inboxIDs.contains($0) })
    }

    @Test("Когда день занят, задачи «Без даты» не встают и не считаются перенесёнными")
    func fullDayLeavesInboxAlone() {
        let inbox = [task(1, "Посмотреть новые AI-модели"), task(2, "Изучить новый API")]
        let long = (0..<6).map { index in
            LineaTask(id: UUID(uuidString: "62000000-0000-0000-0000-00000000000\(index)")!,
                      title: "Большая задача \(index)", date: WowFixture.today, priority: .important,
                      createdAt: WowFixture.created.addingTimeInterval(TimeInterval(index)), estimatedMinutes: 120)
        }
        let plan = PlanFixture.engine().plan(
            snapshot: PlanFixture.snapshot(tasks: long + inbox, at: time),
            state: PlanFixture.reducedState(at: time), time: time, planID: WowFixture.planID
        )
        let inboxIDs = Set(inbox.map(\.id))
        #expect(plan.focusBlocks.allSatisfy { !($0.taskID.map(inboxIDs.contains) ?? false) })
        #expect(plan.deferredTaskIDs.allSatisfy { !inboxIDs.contains($0) })
        #expect(!plan.deferredTaskIDs.isEmpty, "Задачи дня не поместились — их перенос честный")
    }

    @Test("«Сейчас» предлагает задачу «Без даты», когда на сегодня ничего нет, а задачу дня — первой")
    func nextActionUsesInbox() {
        let models = task(1, "Посмотреть новые AI-модели")
        let low = task(2, "Книгу почитать", priority: .low)
        let at = WowFixture.time(10)
        func record(_ tasks: [LineaTask]) -> DayRecord {
            DayRecord(day: WowFixture.today,
                      snapshot: PlanFixture.snapshot(tasks: tasks, commitments: [], at: at),
                      state: PlanFixture.state(energy: 0.6, confidence: 0.8, advice: .normal, at: at),
                      plan: nil, updatedAt: at.now)
        }
        let useCase = NextActionUseCase(renderer: RuleBasedExplainer())

        let onlyInbox = useCase.run(record: record([models, low]), tasks: [models, low], calibration: .default, time: at)
        #expect(onlyInbox?.option?.title == "Посмотреть новые AI-модели")
        #expect(onlyInbox?.alternatives.isEmpty == true, "«Не срочная» Linea сама не предлагает")

        let mail = LineaTask(id: UUID(uuidString: "62000000-0000-0000-0000-000000000010")!, title: "Разобрать почту",
                             date: WowFixture.today, createdAt: WowFixture.created, estimatedMinutes: 30)
        let withToday = useCase.run(record: record([models, mail]), tasks: [models, mail], calibration: .default, time: at)
        #expect(withToday?.option?.title == "Разобрать почту")
        #expect(withToday?.alternatives.map(\.title) == ["Посмотреть новые AI-модели"])
    }
}
