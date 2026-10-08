import Testing
import Foundation
@testable import LineaCore

/// Связь задачи с целью: Linea ищет её сама, но только подсказывает —
/// «Похоже, относится к: Запустить Линия Beta [Связать]». Не уверена — молчит.
@Suite("Связь задачи с целью")
struct ConceptGoalMatcherTests {
    private let matcher = ConceptGoalMatcher()

    private static let betaID = UUID(uuidString: "5A000000-0000-0000-0000-000000000001")!
    private static let weightID = UUID(uuidString: "5A000000-0000-0000-0000-000000000002")!

    private func goal(_ title: String, id: UUID = betaID, details: String? = nil, current: String? = nil,
                      target: String? = nil, criteria: [String] = [], active: Bool = true) -> LineaGoal {
        LineaGoal(id: id, title: title, createdAt: WowFixture.created, isActive: active, details: details,
                  currentState: current, targetState: target, successCriteria: criteria)
    }

    /// Цель из примера заказчика — так, как её понимает «Новая цель».
    private var richBeta: LineaGoal {
        goal("Запустить закрытую beta Linea",
             details: "У нас уже есть рабочий прототип приложения. Сейчас идёт переработка задач и онбординга. "
                + "Хотим, чтобы приложение было доступно через TestFlight и подключить 50 тестировщиков.",
             current: "Уже есть рабочий прототип приложения. Идёт переработка задач и онбординга.",
             target: "Приложение доступно через TestFlight и подключить 50 тестировщиков.",
             criteria: ["Приложение доступно через TestFlight", "Подключить 50 тестировщиков"])
    }

    // MARK: Пример заказчика

    @Test("«Опубликовать сборку в TestFlight» — похоже на «Запустить Линия Beta», хотя общих слов нет")
    func customerExample() throws {
        let beta = goal("Запустить Линия Beta")
        #expect(ConceptGoalMatcher.terms("Опубликовать сборку в TestFlight") == ["#launch", "#build", "#beta"])
        #expect(ConceptGoalMatcher.terms("Запустить Линия Beta") == ["#launch", "#linea", "#beta"])
        let match = try #require(matcher.bestMatch(for: "Опубликовать сборку в TestFlight", in: [beta]))
        #expect(match.goalID == Self.betaID)
        #expect(match.score >= matcher.threshold)
    }

    @Test("Цель читается целиком: результат, признаки успеха и рассказ")
    func wholeGoal() {
        for title in ["Опубликовать сборку в TestFlight", "Проверить онбординг", "Найти 50 тестировщиков",
                      "Обновить макеты приложения", "Разработка Linea: бета"] {
            #expect(matcher.bestMatch(for: title, in: [richBeta])?.goalID == Self.betaID, "«\(title)»")
        }
        // Онбординг есть только в рассказе — без него связи не видно.
        #expect(matcher.bestMatch(for: "Проверить онбординг", in: [goal("Запустить Линия Beta")]) == nil)
    }

    @Test("Другие темы: спорт к весу, чтение к книгам, урок к языку")
    func otherTopics() {
        let weight = goal("Похудеть на 5 кг", id: Self.weightID)
        #expect(matcher.bestMatch(for: "Тренировка в зале", in: [weight])?.goalID == Self.weightID)
        #expect(matcher.bestMatch(for: "Записаться в спортзал", in: [weight])?.goalID == Self.weightID)
        #expect(matcher.bestMatch(for: "Читать 20 минут", in: [goal("Прочитать 12 книг за год")]) != nil)
        #expect(matcher.bestMatch(for: "Урок английского", in: [goal("Выучить English до B2")]) != nil)
        #expect(matcher.bestMatch(for: "Подготовить КП для клиента", in: [goal("Увеличить продажи")]) != nil)
        #expect(matcher.bestMatch(for: "Купить кроссовки для бега", in: [goal("Пробежать полумарафон")]) != nil)
    }

    // MARK: Не уверена — молчит

    @Test("Общий глагол или случайное слово — не связь")
    func weakEvidence() {
        let beta = goal("Запустить Линия Beta")
        #expect(matcher.bestMatch(for: "Купить молоко", in: [beta]) == nil)
        #expect(matcher.bestMatch(for: "Запустить стиральную машину", in: [beta]) == nil)
        #expect(matcher.bestMatch(for: "Позвонить на горячую линию банка", in: [beta]) == nil)
        #expect(matcher.bestMatch(for: "Позвонить на линию поддержки", in: [beta]) == nil)
        #expect(matcher.bestMatch(for: "Сдать тест по английскому", in: [richBeta]) == nil)
        #expect(matcher.bestMatch(for: "Подготовить отчёт", in: [goal("Подготовить марафон")]) == nil)
        #expect(matcher.bestMatch(for: "Сделать", in: [beta]) == nil)
    }

    @Test("Две одинаково похожие цели — подсказки нет; явный лидер — есть")
    func ambiguity() {
        let first = goal("Запустить Линия Beta")
        let second = goal("Запустить Линия Beta", id: Self.weightID)
        #expect(matcher.bestMatch(for: "Опубликовать сборку в TestFlight", in: [first, second]) == nil)
        let weight = goal("Похудеть на 5 кг", id: Self.weightID)
        #expect(matcher.bestMatch(for: "Опубликовать сборку в TestFlight", in: [weight, first])?.goalID == Self.betaID)
        #expect(matcher.bestMatch(for: "Опубликовать сборку в TestFlight", in: [first, weight])?.goalID == Self.betaID)
    }

    @Test("Неактивные и выполненные цели не предлагаются")
    func skipsInactive() {
        #expect(matcher.bestMatch(for: "Опубликовать сборку в TestFlight", in: [goal("Запустить Линия Beta", active: false)]) == nil)
        var done = goal("Запустить Линия Beta")
        done.isCompleted = true
        #expect(matcher.bestMatch(for: "Опубликовать сборку в TestFlight", in: [done]) == nil)
    }

    @Test("Прежние примеры подсказки по словам работают")
    func formerExamples() {
        let mvp = goal("Запустить MVP Linea")
        #expect(matcher.bestMatch(for: "Разработка Linea: MVP", in: [mvp]) != nil)
        #expect(matcher.bestMatch(for: "Запуск Linea в проде", in: [mvp]) != nil)
        #expect(matcher.bestMatch(for: "Подготовить релиз", in: [mvp]) != nil)
    }

    // MARK: Подсказка для сохранённой задачи

    @Test("Сохранённой задаче подсказывается цель, пока человек не решил сам")
    func savedTaskSuggestion() {
        let linker = GoalLinker()
        let goals = [goal("Запустить Линия Beta")]
        let fresh = LineaTask(title: "Опубликовать сборку в TestFlight", createdAt: WowFixture.created, userFields: [])
        #expect(linker.suggestion(for: fresh, goals: goals)?.goalID == Self.betaID)
        #expect(linker.suggestion(for: fresh, goals: goals)?.source == .suggested)

        // Раньше сохранённая задача — подсказка тоже есть: это не перезапись.
        let legacy = LineaTask(title: "Опубликовать сборку в TestFlight", createdAt: WowFixture.created)
        #expect(linker.suggestion(for: legacy, goals: goals) != nil)

        // Человек сам выбрал «Без цели» — Linea не переспрашивает.
        var declined = fresh
        declined.userFields = [.goal]
        #expect(linker.suggestion(for: declined, goals: goals) == nil)

        var linked = fresh
        linked.goalID = Self.weightID
        #expect(linker.suggestion(for: linked, goals: goals) == nil)
        var done = fresh
        done.isDone = true
        #expect(linker.suggestion(for: done, goals: goals) == nil)
    }

    @Test("Подсказка не связывает: «Связать» — только человек, задача без цели остаётся без цели")
    func suggestionNeverLinks() {
        let goals = [goal("Запустить Линия Beta")]
        let result = QuickTaskDraft(text: "Опубликовать сборку в TestFlight")
            .resolve(goals: goals, profile: WowFixture.profile, time: WowFixture.morning)
        #expect(result.suggestion?.goalID == Self.betaID)
        let task = result.task(id: WowFixture.taskA, createdAt: WowFixture.created)
        #expect(task.goalID == nil)
        #expect(task.userFields?.contains(.goal) == false)

        var linked = QuickTaskDraft(text: "Опубликовать сборку в TestFlight")
        linked.goal = .linked(Self.betaID)
        let chosen = linked.resolve(goals: goals, profile: WowFixture.profile, time: WowFixture.morning)
        #expect(chosen.goalID == Self.betaID)
        #expect(chosen.suggestion == nil)
        #expect(chosen.task(id: WowFixture.taskA, createdAt: WowFixture.created).userFields?.contains(.goal) == true)
    }
}

/// goal_id = null не снижает ценность задачи: без цели она оценивается по
/// своим признакам, а связь с целью может её только поднять.
@Suite("Задача без цели")
struct TaskWithoutGoalTests {
    private let engine = PriorityEngine()
    private let time = WowFixture.time(9)

    private func importance(_ task: LineaTask, goals: [LineaGoal] = WowFixture.goals) -> Double {
        let snapshot = PlanFixture.snapshot(tasks: [task], commitments: [], goals: goals, at: time)
        let context = PriorityContext(snapshot: snapshot, state: PlanFixture.state(energy: 0.6, confidence: 0.8, advice: .normal, at: time), time: time)
        return engine.importance(of: task, at: time.now, context: context).score
    }

    @Test("Без цели — по своим признакам: вес цели делится между ними")
    func ownMerit() {
        let contract = LineaTask(title: "Отправить договор", createdAt: WowFixture.created)
        let expected = (0.30 * 0.5 + 0.25 * TaskScorer.neutralUrgency + 0.10 * 0.9) / 0.75
        #expect(abs(importance(contract) - expected) < 1e-9)
    }

    @Test("Связь с целью не опускает: срочное важное с целью — не ниже, чем без неё")
    func linkNeverLowers() {
        var low = WowFixture.goals[0]
        low.priority = .low
        let urgent = LineaTask(title: "Отправить КП клиенту", date: WowFixture.today, priority: .important,
                               createdAt: WowFixture.created, deadline: WowFixture.moment(12), estimatedMinutes: 60)
        var linked = urgent
        linked.goalID = low.id
        #expect(importance(linked, goals: [low]) == importance(urgent, goals: [low]))
    }

    @Test("Связь с важной горящей целью — поднимает")
    func linkCanRaise() {
        var hot = WowFixture.goals[0]
        hot.priority = .important
        let plain = LineaTask(title: "Сделать лендинг", createdAt: WowFixture.created)
        var linked = plain
        linked.goalID = hot.id
        #expect(importance(linked, goals: [hot]) > importance(plain, goals: [hot]))
    }

    @Test("Срочное важное без цели важнее рядового шага к цели")
    func urgentWithoutGoalComesFirst() {
        let beta = LineaGoal(id: UUID(uuidString: "5B000000-0000-0000-0000-000000000001")!, title: "Запустить Линия Beta",
                             createdAt: WowFixture.created, priority: .important)
        let offer = LineaTask(title: "Отправить КП клиенту", date: WowFixture.today, priority: .important,
                              createdAt: WowFixture.created, deadline: WowFixture.moment(19), estimatedMinutes: 60)
        let step = LineaTask(title: "Опубликовать сборку в TestFlight", date: WowFixture.today,
                             createdAt: WowFixture.created, estimatedMinutes: 30, goalID: beta.id)
        #expect(importance(offer, goals: [beta]) > importance(step, goals: [beta]))
    }
}
