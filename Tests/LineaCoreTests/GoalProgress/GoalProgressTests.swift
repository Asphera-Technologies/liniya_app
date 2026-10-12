import Testing
import Foundation
@testable import LineaCore

/// Прогресс цели — по её методу. Процент — только когда его можно честно
/// посчитать. Время — среда 9 сентября 2026, 08:00 по Москве.
@Suite("Прогресс цели")
struct GoalProgressTests {
    private let time = WowFixture.morning
    private let engine = GoalProgressEngine()
    private let goalID = UUID(uuidString: "60A10000-0000-0000-0000-000000000001")!

    private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "60A20000-0000-0000-0000-%012d", n))! }

    private func goal(_ method: GoalProgressMethod, configure: (inout LineaGoal) -> Void = { _ in }) -> LineaGoal {
        var goal = LineaGoal(id: goalID, title: "Запустить Линия Beta", createdAt: WowFixture.created, progressMethod: method)
        configure(&goal)
        return goal
    }

    private func progress(_ goal: LineaGoal, tasks: [LineaTask] = []) -> GoalProgress {
        engine.progress(of: goal, tasks: tasks, time: time)
    }

    private func text(_ goal: LineaGoal, tasks: [LineaTask] = []) -> String {
        GoalProgressText.summary(progress(goal, tasks: tasks), time: time)
    }

    // MARK: metric

    @Test("Число: 18 из 50 пользователей — 36%")
    func metric() {
        let users = goal(.metric) { $0.metrics = [GoalMetric(id: id(1), unit: "пользователей", current: 18, target: 50)] }
        let result = progress(users)
        #expect(result.value == 0.36)
        #expect(result.bar == .fraction(0.36))
        #expect(GoalProgressText.metric(users.metrics[0]) == "18 из 50 пользователей")
        #expect(text(users) == "18 из 50 пользователей · 36%")
    }

    @Test("Изменение числа обновляет прогресс")
    func metricChangeUpdatesProgress() {
        var users = goal(.metric) { $0.metrics = [GoalMetric(id: id(1), unit: "пользователей", current: 18, target: 50)] }
        users.metrics[0].current = 25
        #expect(progress(users).value == 0.5)
        #expect(text(users) == "25 из 50 пользователей · 50%")
    }

    @Test("Число вниз: 78 кг при старте 80 и цели 75 — 40%, перебор — 100%")
    func decreasingMetric() {
        let weight = goal(.metric) { $0.metrics = [GoalMetric(id: id(1), unit: "кг", start: 80, current: 78, target: 75)] }
        #expect(abs((progress(weight).value ?? 0) - 0.4) < 1e-9)
        #expect(text(weight) == "78 кг, цель — 75 кг · 40%")

        var beyond = weight
        beyond.metrics[0].current = 74
        #expect(progress(beyond).value == 1)
    }

    @Test("Числа нет или цель равна старту — процента нет")
    func metricWithoutTarget() {
        #expect(progress(goal(.metric)).value == nil)
        #expect(text(goal(.metric)) == "Число не задано")
        let flat = goal(.metric) { $0.metrics = [GoalMetric(id: id(1), unit: "км", start: 10, current: 10, target: 10)] }
        #expect(progress(flat).value == nil)
        #expect(progress(flat).bar == nil)
    }

    // MARK: milestones

    private var appMilestones: [GoalMilestone] {
        [
            GoalMilestone(id: id(1), title: "Core loop", completedAt: WowFixture.moment(10, dayOffset: -3)),
            GoalMilestone(id: id(2), title: "Onboarding"),
            GoalMilestone(id: id(3), title: "Аналитика"),
            GoalMilestone(id: id(4), title: "QA"),
            GoalMilestone(id: id(5), title: "TestFlight"),
        ]
    }

    @Test("Этапы без весов: «1 из 5 этапов», отрезками, без процента")
    func milestonesWithoutWeights() {
        let app = goal(.milestones) { $0.milestones = appMilestones }
        let result = progress(app)
        #expect(result.value == nil, "Без уверенных весов точности нет")
        #expect(result.bar == .steps(done: 1, total: 5))
        #expect(result.nextMilestone?.title == "Onboarding")
        #expect(text(app) == "1 из 5 этапов")
    }

    @Test("Этапы с весами: Core loop 30 из 100 — 30%; закрытие этапа обновляет прогресс")
    func weightedMilestones() {
        var app = goal(.milestones) {
            $0.milestones = appMilestones
            for (index, weight) in [30.0, 15, 15, 20, 20].enumerated() { $0.milestones[index].weight = weight }
        }
        #expect(progress(app).value == 0.3)
        #expect(text(app) == "1 из 5 этапов · 30%")

        app.milestones[1].completedAt = WowFixture.moment(7)
        #expect(progress(app).value == 0.45)
        #expect(progress(app).nextMilestone?.title == "Аналитика")
        #expect(text(app) == "2 из 5 этапов · 45%")
    }

    @Test("Вес есть не у всех этапов — процента нет")
    func partialWeights() {
        let app = goal(.milestones) {
            $0.milestones = appMilestones
            $0.milestones[0].weight = 30
        }
        #expect(progress(app).value == nil)
        #expect(text(app) == "1 из 5 этапов")
    }

    @Test("Этапов нет — так и сказано")
    func noMilestones() {
        #expect(text(goal(.milestones)) == "Этапы не заданы")
        #expect(progress(goal(.milestones)).bar == nil)
    }

    // MARK: hybrid

    @Test("Этапы и числа: рядом, общего процента нет, следующий рубеж — первый открытый этап")
    func hybrid() {
        let beta = goal(.hybrid) {
            $0.milestones = [
                GoalMilestone(id: id(1), title: "Запуск приложения", completedAt: WowFixture.moment(10, dayOffset: -5)),
                GoalMilestone(id: id(2), title: "25 активных пользователей"),
            ]
            $0.metrics = [
                GoalMetric(id: id(3), unit: "пользователей", current: 18, target: 50),
                GoalMetric(id: id(4), unit: "интервью", current: 7, target: 20),
            ]
        }
        let result = progress(beta)
        #expect(result.value == nil)
        #expect(result.metrics.count == 2)
        #expect(result.nextMilestone?.title == "25 активных пользователей")
        #expect(result.bar == .steps(done: 1, total: 2))
        #expect(text(beta) == "18 из 50 пользователей · 1 из 2 этапов")
        #expect(GoalProgressText.metric(result.metrics[1]) == "7 из 20 интервью")
    }

    // MARK: manual

    @Test("Отмечаю сам: слова вместо процента")
    func manual() {
        let goal = goal(.manual) { $0.manualState = .almostDone }
        let result = progress(goal)
        #expect(result.value == nil)
        #expect(result.bar == nil)
        #expect(text(goal) == "Почти готово")
    }

    @Test("Цель со слайдером читается как «Отмечаю сам»: 0,3 — «В процессе», для важности — 0,3 как было")
    func legacySlider() {
        let legacy = LineaGoal(id: goalID, title: "Запустить MVP Linea", progress: 0.3, createdAt: WowFixture.created)
        #expect(legacy.progressMethod == .manual)
        #expect(legacy.reportedState == .inProgress)
        #expect(text(legacy) == "В процессе")
        #expect(GoalProgressEngine.completion(of: legacy) == 0.3)
        #expect(GoalManualState.from(legacyProgress: 0) == .started)
        #expect(GoalManualState.from(legacyProgress: 0.8) == .almostDone)
        #expect(GoalManualState.from(legacyProgress: 1) == .done)
    }

    // MARK: qualitative

    @Test("Без процентов: стадия, последнее продвижение, значимые действия за 30 дней")
    func qualitative() {
        let brand = LineaGoal(
            id: goalID, title: "Развить личный бренд", createdAt: WowFixture.created,
            stages: ["Позиционирование", "Формирование регулярного контента", "Рост аудитории"],
            stage: "Формирование регулярного контента",
            progressMethod: .qualitative,
            progressLog: [
                GoalProgressEvent(kind: .stageChanged, at: WowFixture.moment(12, dayOffset: -40), detail: "Формирование регулярного контента"),
            ]
        )
        let posts = (1...5).map { day in
            LineaTask(id: id(10 + day), title: "Пост \(day)", isDone: true, createdAt: WowFixture.created,
                      goalID: goalID, completedAt: WowFixture.moment(19, dayOffset: -day))
        }
        let other = LineaTask(id: id(30), title: "Чужая задача", isDone: true, createdAt: WowFixture.created,
                              completedAt: WowFixture.moment(19))
        let open = LineaTask(id: id(31), title: "Открытая", createdAt: WowFixture.created, goalID: goalID)
        let result = progress(brand, tasks: posts + [other, open])
        #expect(result.value == nil, "Личный бренд в процентах не выражается")
        #expect(result.bar == nil)
        #expect(result.recentActions == 5, "Событие 40 дней назад — за окном")
        #expect(result.lastProgressAt == WowFixture.moment(19, dayOffset: -1))

        let lines = GoalProgressText.qualitativeLines(result, time: time)
        #expect(lines.map(\.label) == ["Текущая стадия", "Последнее продвижение", "За 30 дней"])
        #expect(lines.map(\.value) == ["Формирование регулярного контента", "вчера", "5 значимых действий"])
        #expect(text(brand, tasks: posts) == "Формирование регулярного контента · последнее продвижение — вчера")
        #expect(text(goal(.qualitative)) == "Продвижений пока нет")
    }

    @Test("Мелкие задачи не двигают процент: закрытые задачи цели — не доля пути")
    func tasksDoNotMoveProgress() {
        let users = goal(.metric) { $0.metrics = [GoalMetric(id: id(1), unit: "пользователей", current: 18, target: 50)] }
        let tasks = (1...10).map { n in
            LineaTask(id: id(40 + n), title: "Мелочь \(n)", isDone: true, createdAt: WowFixture.created,
                      goalID: goalID, completedAt: WowFixture.moment(7, dayOffset: -1))
        }
        #expect(progress(users, tasks: tasks).value == 0.36)
        #expect(progress(users, tasks: tasks).recentActions == 10, "Но они — значимые действия")
        #expect(progress(goal(.milestones), tasks: tasks).value == nil)
        #expect(GoalProgressEngine.completion(of: goal(.qualitative)) == nil)
    }

    @Test("Выполненная цель — «Выполнено» и полная полоска при любом методе")
    func completed() {
        let done = goal(.qualitative) { $0.isCompleted = true }
        #expect(text(done) == "Выполнено")
        #expect(progress(done).bar == .fraction(1))
        #expect(GoalProgressEngine.completion(of: done) == 1)
    }

    // MARK: Тексты

    @Test("Числа, проценты и даты по-русски")
    func texts() {
        #expect(GoalProgressText.number(18) == "18")
        #expect(GoalProgressText.number(2.5) == "2,5")
        #expect(GoalProgressText.number(1000) == "1000")
        #expect(GoalProgressText.number(300_000) == "300\u{00A0}000")
        #expect(GoalProgressText.number(1.999) == "2")
        #expect(GoalProgressText.percent(0.355) == "36%")
        #expect(GoalProgressText.milestones(done: 1, total: 1) == "1 из 1 этапа")
        #expect(GoalProgressText.milestones(done: 2, total: 21) == "2 из 21 этапа")
        #expect(GoalProgressText.actions(1) == "1 значимое действие")
        #expect(GoalProgressText.actions(3) == "3 значимых действия")
        #expect(GoalProgressText.actions(0) == "ни одного значимого действия")
        #expect(GoalProgressText.moment(WowFixture.moment(7), time: time) == "сегодня")
        #expect(GoalProgressText.moment(WowFixture.moment(7, dayOffset: -3), time: time) == "3 дня назад")
        #expect(GoalProgressText.moment(WowFixture.moment(7, dayOffset: -20), time: time) == "20 августа")
        #expect(GoalProgressText.deadline(WowFixture.moment(0, dayOffset: 36), time: time) == "до 15 октября")
        #expect(GoalProgressText.shortDeadline(WowFixture.moment(0, dayOffset: 36), time: time) == "до 15 окт")
        #expect(GoalProgressText.deadline(WowFixture.moment(0, dayOffset: 400), time: time) == "до 14 октября 2027")
    }

    // MARK: Важность задач

    @Test("Почти достигнутая цель тянет слабее — по её методу; цель без процентов не ослабевает")
    func alignmentUsesHonestCompletion() {
        let scorer = TaskScorer()
        let slot = WowFixture.moment(9)

        func alignment(_ configure: (inout LineaGoal) -> Void) -> Double {
            var goal = WowFixture.goals[0]
            goal.endDate = WowFixture.today
            configure(&goal)
            var snapshot = WowFixture.snapshot(at: time)
            snapshot.goals = [goal]
            let task = snapshot.tasks.first { $0.id == WowFixture.taskA }!
            return scorer.goalAlignment(task: task, snapshot: snapshot, at: slot, time: time)
        }

        let fresh = alignment { $0.progress = 0 }
        let almost = alignment {
            $0.progressMethod = .metric
            $0.metrics = [GoalMetric(id: id(1), unit: "пользователей", current: 45, target: 50)]
        }
        let brand = alignment {
            $0.progressMethod = .qualitative
            $0.progress = 0.9
        }
        #expect(almost < fresh)
        #expect(brand == fresh, "Без процентов цель тянет как новая, что бы ни лежало в старом слайдере")
    }
}
