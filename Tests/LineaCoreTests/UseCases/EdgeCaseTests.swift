import Testing
import Foundation
@testable import LineaCore

/// Дни, которые случатся у настоящего пользователя раньше, чем красивый
/// wow-сценарий: первый запуск без истории, пустой день, поздний вечер,
/// просроченное со вчера, другой часовой пояс.
@Suite("Граничные дни")
struct EdgeCaseTests {
    private let explainer = RuleBasedExplainer()

    private func useCase(providers: [any ContextProvider] = []) -> PlanDayUseCase {
        PlanDayUseCase(
            contextEngine: ContextEngine(providers: providers),
            decisionEngine: DecisionEngine(rules: [DayBriefRule()], renderer: explainer),
            nudgeEngine: NudgeEngine(renderer: explainer),
            explainer: explainer
        )
    }

    private func input(
        time: TimeContext,
        tasks: [LineaTask] = [],
        goals: [LineaGoal] = [],
        history: [DailyHealthSummary] = []
    ) -> PlanDayUseCase.Input {
        PlanDayUseCase.Input(
            time: time, tasks: tasks, goals: goals,
            profile: WowFixture.profile, nutrition: nil, meals: [],
            history: history, calibration: .default
        )
    }

    @Test("Первый запуск: ни данных, ни задач — и ни одного придуманного слова")
    func firstLaunch() async throws {
        let output = await useCase().run(input(time: WowFixture.morning))
        let state = try #require(output.record.state)
        #expect(state.loadAdvice == .unknown)
        #expect(state.confidence == 0)

        let brief = try #require(output.record.plan?.brief)
        #expect(brief.message == "Доброе утро. На сегодня задач нет.")
        #expect(!brief.message.contains("обычн"))
        #expect(output.record.plan?.blocks.isEmpty == true)
        #expect(output.insight.recentNights.isEmpty)
    }

    @Test("День без задач, но с данными о сне: состояние есть, планировать нечего")
    func emptyDayWithHealth() async throws {
        let output = await useCase(providers: [
            FakeContextProvider(id: .healthKit, signals: WowFixture.healthSignals),
        ]).run(input(time: WowFixture.morning, history: WowFixture.history))

        #expect(output.record.state?.loadAdvice == .reduce)
        #expect(output.record.plan?.blocks.isEmpty == true)
        let brief = try #require(output.record.plan?.brief)
        #expect(brief.message.contains("На сегодня задач нет."))
        // Причина названа: сон ниже нормы, даже если планировать нечего.
        #expect(brief.facts.contains { if case .sleepVsUsual = $0 { return true }; return false })
    }

    @Test("Поздний вечер: рабочий день кончился, блоков нет")
    func lateEvening() async throws {
        let output = await useCase().run(input(time: WowFixture.time(23, 10), tasks: WowFixture.tasks))
        #expect(output.record.plan?.focusBlocks.isEmpty == true)
        #expect(output.record.plan?.brief != nil)
    }

    @Test("Просроченная со вчера задача не теряется и получает максимальную срочность")
    func overdueTaskIsPlanned() async throws {
        let overdue = LineaTask(
            id: UUID(uuidString: "FFFFFFFF-0000-0000-0000-00000000000F")!,
            title: "Отправить отчёт",
            date: WowFixture.moment(0, 0, dayOffset: -1),
            priority: .normal,
            createdAt: WowFixture.created,
            deadline: WowFixture.moment(18, 0, dayOffset: -1),
            estimatedMinutes: 30,
            cognitiveDemand: .normal
        )
        let output = await useCase().run(
            input(time: WowFixture.morning, tasks: [overdue] + WowFixture.tasks, goals: WowFixture.goals)
        )
        let plan = try #require(output.record.plan)
        let block = try #require(plan.block(for: overdue.id))
        #expect(block.score?.urgency == 1)

        // Срочность — только 30% оценки: важная задача с дедлайном сегодня и
        // привязкой к цели законно обгоняет просроченную рутину.
        let presentation = try #require(plan.block(for: WowFixture.taskA))
        #expect(presentation.start < block.start)
        #expect((presentation.score?.total ?? 0) > (block.score?.total ?? 1))
    }

    @Test("Просроченная важная задача с целью идёт первой")
    func overdueImportantTaskGoesFirst() async throws {
        let overdue = LineaTask(
            id: UUID(uuidString: "FFFFFFFF-0000-0000-0000-00000000000E")!,
            title: "Сдать КП заказчику",
            date: WowFixture.moment(0, 0, dayOffset: -1),
            priority: .important,
            createdAt: WowFixture.created,
            deadline: WowFixture.moment(18, 0, dayOffset: -1),
            estimatedMinutes: 30,
            cognitiveDemand: .normal,
            goalID: WowFixture.goalMVP
        )
        let output = await useCase().run(
            input(time: WowFixture.morning, tasks: [overdue] + WowFixture.tasks, goals: WowFixture.goals)
        )
        let plan = try #require(output.record.plan)
        let first = try #require(plan.focusBlocks.min { $0.start < $1.start })
        #expect(first.taskID == overdue.id)
    }

    @Test("Тот же день в другом часовом поясе планируется по местным часам")
    func timeZoneShift() async throws {
        let moscow = WowFixture.morning
        let lisbon = TimeContext(now: moscow.now, timeZoneIdentifier: "Europe/Lisbon")

        let a = await useCase().run(input(time: moscow, tasks: WowFixture.tasks, goals: WowFixture.goals))
        let b = await useCase().run(input(time: lisbon, tasks: WowFixture.tasks, goals: WowFixture.goals))

        let firstMoscow = try #require(a.record.plan?.focusBlocks.first)
        let firstLisbon = try #require(b.record.plan?.focusBlocks.first)
        // 08:00 в Москве — это 06:00 в Лиссабоне: рабочий день ещё не начался,
        // поэтому первый блок встаёт на 09:00 по местному времени.
        #expect(moscow.timeOfDay(of: firstMoscow.start).hour == 9)
        #expect(lisbon.timeOfDay(of: firstLisbon.start).hour == 9)
        #expect(firstMoscow.start != firstLisbon.start)
    }

    @Test("Задача длиннее остатка дня не выкидывается молча")
    func taskLongerThanTheDay() async throws {
        let huge = LineaTask(
            id: UUID(uuidString: "AAAAAAAA-1111-0000-0000-00000000000A")!,
            title: "Переписать всё",
            date: WowFixture.today,
            createdAt: WowFixture.created,
            estimatedMinutes: 10 * 60,
            cognitiveDemand: .deep
        )
        let output = await useCase().run(input(time: WowFixture.time(19, 0), tasks: [huge]))
        let plan = try #require(output.record.plan)
        let planned = plan.focusBlocks.contains { $0.taskID == huge.id }
        let deferred = plan.deferredTaskIDs.contains(huge.id)
        #expect(planned || deferred)
    }

    @Test("Без обязательств впереди напоминание считает конец рабочего дня")
    func nudgeWithoutCommitments() async throws {
        let task = LineaTask(
            id: WowFixture.taskA, title: "Презентация КП", date: WowFixture.today,
            priority: .important, createdAt: WowFixture.created,
            estimatedMinutes: 60, cognitiveDemand: .deep
        )
        let built = await useCase().run(input(time: WowFixture.morning, tasks: [task]))
        let accepted = AcceptPlanUseCase(nudgeEngine: NudgeEngine(renderer: explainer))
            .run(record: built.record, calibration: .default, time: WowFixture.morning)

        let checkIn = CheckInUseCase(nudgeEngine: NudgeEngine(renderer: explainer))
            .run(record: accepted.record, tasks: [task], calibration: .default, time: WowFixture.time(12, 0))
        let nudge = try #require(checkIn.due)
        #expect(nudge.facts.contains { if case .endOfWorkday = $0 { return true }; return false })
        #expect(nudge.body.contains("До конца рабочего дня"))
    }

    @Test("Повторный сбор в тот же день не плодит новые идентификаторы")
    func stableIdentifiers() async throws {
        let first = await useCase().run(input(time: WowFixture.morning, tasks: WowFixture.tasks))
        let second = await useCase().run(input(time: WowFixture.time(11, 0), tasks: WowFixture.tasks))
        #expect(first.record.plan?.id == second.record.plan?.id)
    }
}
