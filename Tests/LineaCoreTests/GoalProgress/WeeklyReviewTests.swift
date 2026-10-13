import Testing
import Foundation
@testable import LineaCore

/// Мягкий обзор прогресса за неделю: сколько продвижений по каждой цели и
/// одно наблюдение — без оценки человека. Среда 9 сентября 2026, Москва;
/// неделя — с понедельника 7-го по воскресенье 13-го.
@Suite("Обзор недели")
struct WeeklyReviewTests {
    private let builder = WeeklyReviewBuilder()
    private let time = WowFixture.time(18)

    private var week: DateInterval {
        DateInterval(start: WowFixture.moment(0, 0, dayOffset: -2), end: WowFixture.moment(0, 0, dayOffset: 5))
    }

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "3EE00000-0000-0000-0000-%012d", n))!
    }

    private var beta: LineaGoal {
        LineaGoal(id: id(100), title: "Linea Beta", createdAt: WowFixture.created, priority: .important)
    }

    private var sales: LineaGoal {
        LineaGoal(id: id(200), title: "Asphera Sales", createdAt: WowFixture.created)
    }

    /// Закрытая задача: в какой день недели (смещение от среды), сколько минут.
    private func done(_ n: Int, _ title: String, dayOffset: Int, minutes: Int, goal: UUID? = nil) -> LineaTask {
        LineaTask(id: id(n), title: title, date: WowFixture.moment(0, 0, dayOffset: dayOffset), isDone: true,
                  createdAt: WowFixture.created, estimatedMinutes: minutes, goalID: goal,
                  completedAt: WowFixture.moment(12, 0, dayOffset: dayOffset))
    }

    private func meeting(_ n: Int, dayOffset: Int, hours: Int) -> Commitment {
        Commitment(id: "event-\(n)", title: "Встреча с клиентом", start: WowFixture.moment(10, 0, dayOffset: dayOffset),
                   end: WowFixture.moment(10 + hours, 0, dayOffset: dayOffset), kind: .meeting, source: .calendar)
    }

    @Test("Пример заказчика: Linea Beta — 3 продвижения, Asphera Sales — 2, неделя ушла на текущие обязательства")
    func customerExample() throws {
        var sales = sales
        // Число ближе к цели — тоже продвижение.
        sales.progressLog = [GoalProgressEvent(kind: .metricUpdated, at: WowFixture.moment(16, 0, dayOffset: -1), detail: "3")]
        let tasks = [
            done(1, "Собрать сборку", dayOffset: -2, minutes: 60, goal: beta.id),
            done(2, "Онбординг", dayOffset: -1, minutes: 45, goal: beta.id),
            done(3, "Проверить TestFlight", dayOffset: 0, minutes: 30, goal: beta.id),
            done(4, "Позвонить в Asphera", dayOffset: 0, minutes: 30, goal: sales.id),
            done(5, "Отправить договор клиенту", dayOffset: -2, minutes: 60),
            done(6, "Подготовить отчёт для клиента", dayOffset: -1, minutes: 90),
        ]
        let meetings = [meeting(1, dayOffset: -2, hours: 2), meeting(2, dayOffset: -1, hours: 3), meeting(3, dayOffset: 0, hours: 2)]
        let review = try #require(builder.review(week: week, goals: [sales, beta], tasks: tasks, meetings: meetings, time: time))
        #expect(review.title == "На этой неделе")
        #expect(review.goals.map(\.title) == ["Linea Beta", "Asphera Sales"])
        #expect(review.goals.map(\.summary) == ["3 продвижения", "2 продвижения"])
        #expect(review.observation == "Большая часть недели ушла на текущие обязательства. По «Linea Beta» получилось продвинуться трижды.")
    }

    @Test("Без оценки человека: ни «молодец», ни «мало», ни «отстаёшь»")
    func noJudgement() throws {
        let tasks = [
            done(1, "Сборка", dayOffset: -2, minutes: 90, goal: beta.id),
            done(2, "Онбординг", dayOffset: -1, minutes: 90, goal: beta.id),
            done(3, "Купить продукты", dayOffset: 0, minutes: 20),
        ]
        let review = try #require(builder.review(week: week, goals: [beta, sales], tasks: tasks, time: time))
        #expect(review.observation == "Большая часть недели ушла на цели. По «Linea Beta» получилось продвинуться дважды.")
        #expect(review.goals.last?.summary == "пока без продвижений")
        let words = (review.goals.map(\.summary) + [review.observation ?? ""]).joined(separator: " ").lowercased()
        for judgement in ["молодец", "мало", "отста", "плохо", "хорошо", "лучше", "хуже", "надо", "должен"] {
            #expect(!words.contains(judgement), "Без оценки: «\(judgement)»")
        }
    }

    @Test("Поровну — «поделилась»; шагов к целям не было — так и сказано")
    func balancedAndNoSteps() throws {
        let balanced = [
            done(1, "Сборка", dayOffset: -2, minutes: 60, goal: beta.id),
            done(2, "Оплатить интернет", dayOffset: -1, minutes: 30),
            done(3, "Купить продукты", dayOffset: 0, minutes: 30),
        ]
        #expect(builder.review(week: week, goals: [beta], tasks: balanced, time: time)?.observation
                == "Неделя поделилась между текущими делами и целями. По «Linea Beta» получилось продвинуться один раз.")

        let current = [
            done(1, "Оплатить интернет", dayOffset: -2, minutes: 30),
            done(2, "Купить продукты", dayOffset: -1, minutes: 30),
            done(3, "Разобрать почту", dayOffset: 0, minutes: 30),
        ]
        #expect(builder.review(week: week, goals: [beta], tasks: current, time: time)?.observation
                == "Большая часть недели ушла на текущие дела. Шагов к целям на этой неделе пока не было.")
    }

    @Test("Данных мало — только продвижения, без наблюдения; целей нет — обзора нет")
    func littleData() throws {
        let review = try #require(builder.review(week: week, goals: [beta], tasks: [done(1, "Сборка", dayOffset: 0, minutes: 30, goal: beta.id)],
                                                 time: time))
        #expect(review.goals.map(\.summary) == ["1 продвижение"])
        #expect(review.observation == nil)
        #expect(builder.review(week: week, goals: [], tasks: [], time: time) == nil)
        let nextWeek = DateInterval(start: week.end, duration: 7 * 86_400)
        #expect(builder.review(week: nextWeek, goals: [beta], tasks: [], time: time) == nil, "Неделя ещё не началась")
    }

    @Test("Считается только эта неделя и только то, что уже было; отменённое — не в счёт")
    func onlyThisWeek() throws {
        var cancelled = done(3, "Отменённая", dayOffset: 0, minutes: 30, goal: beta.id)
        cancelled.cancelledAt = WowFixture.moment(13)
        let tasks = [
            done(1, "Прошлая неделя", dayOffset: -4, minutes: 30, goal: beta.id),
            done(2, "Эта неделя", dayOffset: -1, minutes: 30, goal: beta.id),
            cancelled,
        ]
        var goal = beta
        goal.progressLog = [GoalProgressEvent(kind: .milestoneDone, at: WowFixture.moment(10, 0, dayOffset: -5)),
                            GoalProgressEvent(kind: .stageChanged, at: WowFixture.moment(11, 0, dayOffset: 0))]
        let review = try #require(builder.review(week: week, goals: [goal], tasks: tasks, time: time))
        #expect(review.goals.first?.advances == 2, "Задача этой недели и стадия этой недели")
    }

    @Test("Прошлая неделя: «На неделе 31 авг – 6 сен», без «пока»")
    func pastWeek() throws {
        let past = DateInterval(start: WowFixture.moment(0, 0, dayOffset: -9), end: week.start)
        let tasks = [
            done(1, "Оплатить интернет", dayOffset: -8, minutes: 60),
            done(2, "Купить продукты", dayOffset: -7, minutes: 60),
            done(3, "Разобрать почту", dayOffset: -6, minutes: 60),
        ]
        let review = try #require(builder.review(week: past, goals: [beta], tasks: tasks, time: time))
        #expect(review.title == "На неделе 31 авг – 6 сен")
        #expect(review.goals.first?.summary == "без продвижений")
        #expect(review.observation == "Большая часть недели ушла на текущие дела. Шагов к целям за неделю не было.")
        let sameMonth = DateInterval(start: WowFixture.moment(0, 0, dayOffset: 5), end: WowFixture.moment(0, 0, dayOffset: 12))
        #expect(WeeklyReviewBuilder.title(week: sameMonth, isCurrent: false, time: time) == "На неделе 14–20 сен")
        #expect(WeeklyReviewBuilder.times(4) == "4 раза")
        #expect(WeeklyReviewBuilder.times(5) == "5 раз")
        #expect(WeeklyReviewBuilder.summary(5, isCurrent: true) == "5 продвижений")
    }

    @Test("У общей цели — и своя часть: свои задачи и своё число — тоже продвижения")
    func sharedGoal() throws {
        var team = LineaGoal(id: id(300), title: "Выручка 5 млн", createdAt: WowFixture.created, scope: .company,
                             ownerScope: "Enterprise-клиенты")
        team.progressLog = [GoalProgressEvent(kind: .contributionUpdated, at: WowFixture.moment(15, 0, dayOffset: -1))]
        let review = try #require(builder.review(week: week, goals: [team],
                                                 tasks: [done(1, "Встреча с enterprise-клиентом", dayOffset: 0, minutes: 60, goal: team.id)],
                                                 time: time))
        #expect(review.goals.first?.advances == 2)
    }
}
