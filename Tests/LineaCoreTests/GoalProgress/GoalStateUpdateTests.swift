import Testing
import Foundation
@testable import LineaCore

/// «Обновить состояние» цели: человек одним действием рассказывает, что
/// изменилось; Linea показывает, как поняла, и меняет цель только после
/// «Подтвердить». Среда 9 сентября 2026, Москва.
@Suite("Обновить состояние цели")
struct GoalStateUpdateTests {
    private let reader = GoalUpdateReader()
    private let time = WowFixture.time(18)
    private let example = "TestFlight уже сделали, onboarding почти готов, но аналитику пока не подключали."

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "5E000000-0000-0000-0000-%012d", n))!
    }

    private var beta: LineaGoal {
        LineaGoal(id: id(100), title: "Запустить Linea Beta", createdAt: WowFixture.created,
                  currentState: "Есть рабочий прототип", stages: GoalStages.launch.stages,
                  stage: "Разработка", progressMethod: .milestones)
    }

    @Test("Пример заказчика: ✓ TestFlight — завершено, ● Onboarding — почти готов, ○ Аналитика — не начата")
    func customerExample() {
        let update = reader.read(example, goal: beta)
        #expect(update.items.map(GoalStateUpdate.line) == [
            "✓ TestFlight — завершено",
            "● Onboarding — почти готов",
            "○ Аналитика — не начата",
        ])
        #expect(update.focusSentence == "Новый фокус: закончить onboarding и подключить аналитику.")
        #expect(update.focus == ["Закончить onboarding", "Подключить аналитику"])
        #expect(!update.isEmpty)
        #expect(update.items.allSatisfy { $0.milestoneID == nil }, "Этапов у цели не было — это новые")
    }

    @Test("Узнаёт этапы цели по словам; закрытый этап снова не открывается")
    func matchesMilestones() throws {
        var goal = beta
        goal.milestones = [
            GoalMilestone(id: id(1), title: "Core loop", completedAt: WowFixture.moment(10, 0, dayOffset: -5)),
            GoalMilestone(id: id(2), title: "Онбординг и onboarding-экраны"),
            GoalMilestone(id: id(3), title: "Аналитика"),
            GoalMilestone(id: id(4), title: "Сборка в TestFlight"),
        ]
        let update = reader.read(example, goal: goal)
        #expect(update.items.map(\.milestoneID) == [id(4), id(2), id(3)])
        #expect(update.items.map(\.title) == ["Сборка в TestFlight", "Онбординг и onboarding-экраны", "Аналитика"])

        let reopened = reader.read("core loop почти готов", goal: goal)
        let applied = reader.applied(reopened, to: goal, at: time.now)
        #expect(applied.milestones[0].isDone, "Путь вперёд: закрытое остаётся закрытым")
    }

    @Test("Ничего не меняется до «Подтвердить»; после — этапы, «Что уже сделано», шаги и история")
    func appliedOnlyOnConfirm() throws {
        let goal = beta
        let update = reader.read(example, goal: goal)
        #expect(goal.milestones.isEmpty, "Прочитать — не значит поменять")

        let applied = reader.applied(update, to: goal, at: time.now)
        #expect(applied.milestones.map(\.title) == ["TestFlight", "Onboarding", "Аналитика"])
        #expect(applied.milestones.map(\.isDone) == [true, false, false])
        #expect(applied.milestones.map(\.state) == [nil, .almostDone, nil])
        #expect(applied.currentState == example)
        #expect(applied.stateHistory == [GoalStateNote(at: time.now, text: "Есть рабочий прототип")], "Прежний контекст не теряется")
        #expect(applied.nextActions == ["Закончить onboarding", "Подключить аналитику"])

        // Закрытые этапы — в журнале продвижений, как при правке карточки.
        let saved = GoalRevision.saved(previous: goal, updated: applied, time: time)
        #expect(saved.progressLog.map(\.kind) == [.milestoneDone])
        #expect(saved.progressLog.first?.detail == "TestFlight")
        #expect(GoalProgressEngine().progress(of: saved, tasks: [], time: time).milestonesDone == 1)
    }

    @Test("Числа цели: «уже 18 пользователей»; у числа появились этапы — «этапы и числа»")
    func metrics() throws {
        var goal = beta
        goal.progressMethod = .metric
        goal.metrics = [GoalMetric(id: id(7), unit: "пользователей", current: 5, target: 50)]
        let update = reader.read("Уже 18 пользователей, лендинг сделали", goal: goal)
        #expect(update.metrics == [GoalStateUpdate.MetricChange(metricID: id(7), unit: "пользователей", from: 5, to: 18)])
        let applied = reader.applied(update, to: goal, at: time.now)
        #expect(applied.metrics.first?.current == 18)
        #expect(applied.progressMethod == .hybrid)
        #expect(applied.milestones.map(\.title) == ["Лендинг"])
    }

    @Test("Стадия: «идёт тестирование» — она; «тестирование закончили» — следующая")
    func stage() {
        #expect(reader.read("Сейчас идёт тестирование", goal: beta).stage == "Тестирование")
        #expect(reader.read("Тестирование закончили", goal: beta).stage == "Запуск")
        #expect(reader.read("Тестирование пока не начинали", goal: beta).stage == nil, "Не начато — стадия прежняя")
        #expect(reader.read("Сейчас идёт тестирование", goal: beta).items.isEmpty, "Стадия — не этап")
    }

    @Test("Нечего понять — нечего и предлагать; слова в роде этапа")
    func emptyAndGender() {
        #expect(reader.read("Да как-то так", goal: beta).isEmpty)
        #expect(GoalStateUpdate.statusText(.notStarted, for: "Тестирование") == "не начато")
        #expect(GoalStateUpdate.statusText(.almostDone, for: "Документация") == "почти готова")
        #expect(GoalStateUpdate.statusText(.almostDone, for: "Onboarding") == "почти готов")
        #expect(GoalStateUpdate.statusText(.inProgress, for: "Аналитика") == "в процессе")
    }

    @Test("Цель, записанная до обновления состояния, читается: шагов и истории нет")
    func legacyDecode() throws {
        let old = #"{"id":"\#(id(1).uuidString)","title":"Бег","progress":0,"isCompleted":false,"createdAt":800000000,"milestones":[{"id":"\#(id(2).uuidString)","title":"5 км"}]}"#
        let goal = try JSONDecoder().decode(LineaGoal.self, from: Data(old.utf8))
        #expect(goal.nextActions.isEmpty)
        #expect(goal.stateHistory.isEmpty)
        #expect(goal.milestones.first?.state == nil)
    }
}
