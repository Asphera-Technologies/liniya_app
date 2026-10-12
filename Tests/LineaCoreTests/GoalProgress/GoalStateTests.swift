import Testing
import Foundation
@testable import LineaCore

/// Модель состояния цели: где человек относительно цели, когда пересматривал,
/// что сдвинул вперёд. Время — среда 9 сентября 2026, 08:00 по Москве.
@Suite("Модель состояния цели")
struct GoalStateTests {
    private let time = WowFixture.morning
    private let goalID = UUID(uuidString: "60B10000-0000-0000-0000-000000000001")!

    private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "60B20000-0000-0000-0000-%012d", n))! }

    /// Пример заказчика из постановки.
    private var beta: LineaGoal {
        LineaGoal(
            id: goalID,
            title: "Запустить закрытую beta Linea",
            createdAt: WowFixture.created,
            endDate: WowFixture.moment(0, dayOffset: 36),
            details: "Рабочий прототип готов.",
            currentState: "Рабочий прототип готов. Календарь и HealthKit подключены. Сейчас перерабатывается механика задач и целей.",
            targetState: "Закрытая beta приложения запущена.",
            successCriteria: ["TestFlight опубликован", "50 пользователей получили доступ", "Основные пользовательские сценарии работают"],
            stages: ["Исследование", "Разработка", "Подготовка запуска", "Тестирование", "Запуск", "Рост"],
            stage: "Разработка",
            milestones: [
                GoalMilestone(id: id(1), title: "TestFlight опубликован"),
                GoalMilestone(id: id(2), title: "Основные пользовательские сценарии работают"),
            ],
            metrics: [GoalMetric(id: id(3), unit: "пользователей", current: 0, target: 50)],
            progressMethod: .hybrid,
            scope: .team,
            ownerScope: "Сборки и TestFlight",
            contributionMetrics: [GoalMetric(id: id(4), unit: "сборок", current: 1, target: 3)],
            kindOverride: .project,
            lastReviewedAt: WowFixture.created
        )
    }

    @Test("Цель целиком переживает сохранение: все поля модели состояния на месте")
    func roundTrip() throws {
        let encoded = try JSONEncoder().encode(beta)
        let decoded = try JSONDecoder().decode(LineaGoal.self, from: encoded)
        #expect(decoded == beta)
        #expect(decoded.stage == "Разработка")
        #expect(decoded.stages.count == 6)
        #expect(decoded.scope == .team)
        #expect(decoded.ownerScope == "Сборки и TestFlight")
        #expect(decoded.contributionMetrics.first?.target == 3)
        #expect(decoded.nextMilestone?.title == "TestFlight опубликован")
    }

    @Test("Цель, сохранённая до модели состояния, читается: «Отмечаю сам», своя, без стадии")
    func legacyGoalDecodes() throws {
        let json = """
        {"id":"\(goalID.uuidString)","title":"Запустить MVP Linea","progress":0.6,"isCompleted":false,
         "createdAt":0,"startDate":0,"isActive":true,"priority":"normal","successCriteria":[]}
        """
        let goal = try JSONDecoder().decode(LineaGoal.self, from: Data(json.utf8))
        #expect(goal.progressMethod == .manual)
        #expect(goal.reportedState == .inProgress)
        #expect(goal.scope == .personal)
        #expect(goal.ownerScope == nil)
        #expect(goal.stages.isEmpty)
        #expect(goal.stage == nil)
        #expect(goal.milestones.isEmpty)
        #expect(goal.lastReviewedAt == nil)
    }

    @Test("Незнакомое значение из будущей версии не стоит цели")
    func unknownValuesAreSoft() throws {
        let json = """
        {"id":"\(goalID.uuidString)","title":"Цель","createdAt":0,
         "progressMethod":"telepathy","scope":"galaxy","manualState":"maybe","milestones":[{"oops":1}]}
        """
        let goal = try JSONDecoder().decode(LineaGoal.self, from: Data(json.utf8))
        #expect(goal.progressMethod == .manual)
        #expect(goal.scope == .personal)
        #expect(goal.manualState == nil)
        #expect(goal.milestones.isEmpty)
    }

    @Test("Цель сборки раунда 7: «чья цель» под ключом owner_scope — это не зона ответственности")
    func round7OwnerDecodes() throws {
        let json = #"{"id":"\#(goalID.uuidString)","title":"Ремонт","createdAt":0,"ownerScope":"shared"}"#
        let goal = try JSONDecoder().decode(LineaGoal.self, from: Data(json.utf8))
        #expect(goal.scope == .team, "«Общая» — это команда")
        #expect(goal.ownerScope == nil)
        #expect(GoalScope.legacy("company") == .company)
        #expect(GoalScope.legacy("Продажи") == nil)
    }

    // MARK: Пересмотр и продвижения

    @Test("Сохранение — это пересмотр: время пересмотра — сейчас")
    func saveIsReview() {
        let saved = GoalRevision.saved(previous: beta, updated: beta, time: time)
        #expect(saved.lastReviewedAt == time.now)
        #expect(saved.progressLog.isEmpty, "Ничего не сдвинулось — продвижений нет")
        let created = GoalRevision.saved(previous: nil, updated: beta, time: time)
        #expect(created.lastReviewedAt == time.now)
    }

    @Test("Закрыл этап, приблизил число, перешёл на следующую стадию — три продвижения")
    func forwardMovesAreLogged() {
        var updated = beta
        updated.milestones[0].completedAt = WowFixture.moment(7, 30)
        updated.metrics[0].current = 18
        updated.stage = "Тестирование"
        let saved = GoalRevision.saved(previous: beta, updated: updated, time: time)
        #expect(saved.progressLog.map(\.kind) == [.milestoneDone, .metricUpdated, .stageChanged])
        #expect(saved.progressLog.map(\.detail) == ["TestFlight опубликован", "18 пользователей", "Тестирование"])
        #expect(saved.progressLog[0].at == WowFixture.moment(7, 30), "Этап — когда его закрыли")
        #expect(saved.metrics[0].updatedAt == time.now)
    }

    @Test("Откат — не продвижение: снятый этап, упавшее число, стадия назад и первая стадия не пишутся")
    func backwardMovesAreNotLogged() {
        var progressed = beta
        progressed.milestones[0].completedAt = WowFixture.moment(7)
        progressed.metrics[0].current = 18
        var reverted = progressed
        reverted.milestones[0].completedAt = nil
        reverted.metrics[0].current = 10
        reverted.stage = "Исследование"
        #expect(GoalRevision.progress(from: progressed, to: reverted, at: time.now).isEmpty)

        var unset = beta
        unset.stage = nil
        var first = unset
        first.stage = "Разработка"
        #expect(GoalRevision.progress(from: unset, to: first, at: time.now).isEmpty)
    }

    @Test("Журнал ведётся от сохранённой цели: экран не может его потерять")
    func logComesFromStoredGoal() {
        var stored = beta
        stored.progressLog = [GoalProgressEvent(kind: .stageChanged, at: WowFixture.created, detail: "Разработка")]
        var fromScreen = stored
        fromScreen.progressLog = []
        fromScreen.manualState = .almostDone
        let saved = GoalRevision.saved(previous: stored, updated: fromScreen, time: time)
        #expect(saved.progressLog.count == 2)
        #expect(saved.progressLog.last?.kind == .manualStateChanged)
        #expect(saved.progressLog.last?.detail == "Почти готово")
    }

    @Test("Журнал не растёт бесконечно")
    func logIsCapped() {
        var stored = beta
        stored.progressLog = (0..<GoalRevision.logLimit).map { _ in
            GoalProgressEvent(kind: .metricUpdated, at: WowFixture.created)
        }
        var updated = stored
        updated.metrics[0].current = 5
        let saved = GoalRevision.saved(previous: stored, updated: updated, time: time)
        #expect(saved.progressLog.count == GoalRevision.logLimit)
        #expect(saved.progressLog.last?.detail == "5 пользователей")
    }
}
