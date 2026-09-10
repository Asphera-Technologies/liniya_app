import Testing
import Foundation
@testable import LineaCore

/// Весь сценарий из брифа как один тест: утро → 14:30 → вечер.
/// Если он падает — сломалось обещание продукта, а не деталь реализации.
@Suite("Wow-сценарий целиком")
struct WowScenarioTests {
    private let explainer = RuleBasedExplainer()

    private func useCase(providers: [any ContextProvider]) -> PlanDayUseCase {
        PlanDayUseCase(
            contextEngine: ContextEngine(providers: providers),
            stateEngine: StateEngine(analyzers: StateEngine.defaultAnalyzers + [NutritionFuelAnalyzer()]),
            decisionEngine: DecisionEngine(rules: [DayBriefRule(), NutritionRule()], renderer: explainer),
            nudgeEngine: NudgeEngine(renderer: explainer),
            explainer: explainer
        )
    }

    private var providers: [any ContextProvider] {
        [
            FakeContextProvider(id: .healthKit, signals: WowFixture.healthSignals),
            NutritionContextProvider(profile: WowFixture.nutrition, meals: []),
        ]
    }

    private func morningInput(time: TimeContext = WowFixture.morning, existing: DayRecord? = nil) -> PlanDayUseCase.Input {
        PlanDayUseCase.Input(
            time: time,
            tasks: WowFixture.tasks,
            goals: WowFixture.goals,
            profile: WowFixture.profile,
            nutrition: WowFixture.nutrition,
            meals: [],
            history: WowFixture.history,
            calibration: .default,
            existing: existing
        )
    }

    // MARK: Утро

    @Test("Утро: состояние, план и текст брифа")
    func morning() async throws {
        let output = await useCase(providers: providers).run(morningInput())
        let record = output.record

        let state = try #require(record.state)
        #expect(state.loadAdvice == .reduce)
        #expect(state.sleepNight?.asleepSeconds == 21_780)

        let plan = try #require(record.plan)
        #expect(plan.status == .proposed)
        #expect(plan.topTaskIDs.count == 3)
        #expect(plan.blocks.contains { $0.taskID == WowFixture.taskA && $0.kind == .focus })
        #expect(plan.blocks.contains { $0.kind == .meal })
        #expect(plan.blocks.contains { $0.taskID == WowFixture.taskWorkout && $0.kind == .commitment })

        // Блоки не пересекаются.
        let sorted = plan.blocks.sorted { $0.start < $1.start }
        for (earlier, later) in zip(sorted, sorted.dropFirst()) {
            #expect(earlier.end <= later.start)
        }

        let brief = try #require(plan.brief)
        #expect(brief.message == "Доброе утро. Сегодня нагрузку лучше немного снизить. У тебя есть 3 приоритетных действия. Самую сложную работу предлагаю сделать до 12:00.")

        // Питание связано со здоровьем: сниженная ёмкость → более лёгкий обед.
        #expect(plan.recommendations.contains { $0.kind == .meal })
        #expect(plan.recommendations.contains { $0.kind == .preWorkoutMeal })

        // Аналитика сна для экрана Health посчитана тем же проходом.
        #expect(output.insight.recentNights.isEmpty == false)
        #expect(output.todaySummary[.sleepAsleep] == 21_780)
    }

    @Test("«Принять план» замораживает план и готовит напоминания")
    func acceptPlan() async throws {
        let built = await useCase(providers: providers).run(morningInput())
        let accepted = AcceptPlanUseCase(nudgeEngine: NudgeEngine(renderer: explainer))
            .run(record: built.record, calibration: .default, time: WowFixture.morning)

        #expect(accepted.record.plan?.status == .accepted)
        #expect(accepted.record.plan?.acceptedAt == WowFixture.morning.now)
        #expect(accepted.record.feedback.contains { if case .planAccepted = $0.kind { return true }; return false })
        #expect(!accepted.nudges.isEmpty)
        #expect(accepted.nudges.allSatisfy { $0.fireAt >= WowFixture.morning.now })
    }

    // MARK: 14:30

    @Test("14:30: план отстаёт, и Linea спрашивает ровно то, что обещано")
    func afternoonNudge() async throws {
        let built = await useCase(providers: providers).run(morningInput())
        let accepted = AcceptPlanUseCase(nudgeEngine: NudgeEngine(renderer: explainer))
            .run(record: built.record, calibration: .default, time: WowFixture.morning)

        let checkIn = CheckInUseCase(nudgeEngine: NudgeEngine(renderer: explainer))
            .run(record: accepted.record, tasks: WowFixture.tasks, calibration: .default, time: WowFixture.afternoon)

        let nudge = try #require(checkIn.due)
        #expect(nudge.kind == .behindSchedule)
        #expect(nudge.title == "План немного отстаёт.")
        #expect(nudge.body.contains("Закрываем"))
        #expect(nudge.actions.contains(.deferTask(taskID: nudge.taskID ?? UUID())) || nudge.actions.contains(.finishNow(taskID: nudge.taskID ?? UUID())))
        #expect(nudge.cancelWhen.contains(.taskDone(nudge.taskID ?? UUID())))
    }

    @Test("Выполненная задача снимает напоминание")
    func doneTaskCancelsNudge() async throws {
        let built = await useCase(providers: providers).run(morningInput())
        let accepted = AcceptPlanUseCase(nudgeEngine: NudgeEngine(renderer: explainer))
            .run(record: built.record, calibration: .default, time: WowFixture.morning)

        var tasks = WowFixture.tasks
        for index in tasks.indices { tasks[index].isDone = true }

        let checkIn = CheckInUseCase(nudgeEngine: NudgeEngine(renderer: explainer))
            .run(record: accepted.record, tasks: tasks, calibration: .default, time: WowFixture.afternoon)
        #expect(checkIn.due == nil)
    }

    @Test("«Переносим» записывает решение и просит перенести задачу")
    func deferAnswer() async throws {
        let built = await useCase(providers: providers).run(morningInput())
        let accepted = AcceptPlanUseCase(nudgeEngine: NudgeEngine(renderer: explainer))
            .run(record: built.record, calibration: .default, time: WowFixture.morning)
        let checkIn = CheckInUseCase(nudgeEngine: NudgeEngine(renderer: explainer))
            .run(record: accepted.record, tasks: WowFixture.tasks, calibration: .default, time: WowFixture.afternoon)
        let nudge = try #require(checkIn.due)
        let taskID = try #require(nudge.taskID)

        let answered = RespondToNudgeUseCase().run(
            record: accepted.record, nudge: nudge,
            action: .deferTask(taskID: taskID), time: WowFixture.afternoon
        )
        #expect(answered.effect == .deferTask(taskID: taskID, to: WowFixture.moment(0, 0, dayOffset: 1)))
        #expect(answered.record.feedback.contains { if case .taskPostponed = $0.kind { return true }; return false })
        #expect(!answered.record.nudges.contains { $0.id == nudge.id })
    }

    // MARK: Вечер

    @Test("Вечер: три кнопки меняют завтрашнюю строгость")
    func eveningRating() async throws {
        let built = await useCase(providers: providers).run(morningInput())
        let accepted = AcceptPlanUseCase(nudgeEngine: NudgeEngine(renderer: explainer))
            .run(record: built.record, calibration: .default, time: WowFixture.morning)

        let rated = RecordDayRatingUseCase().run(
            record: accepted.record, rating: .hard, history: [],
            previous: .default, time: WowFixture.evening
        )
        #expect(rated.record.rating == .hard)
        #expect(rated.calibration.ratingsCount == 1)

        // Повторная оценка заменяет первую, а не добавляет вторую.
        let again = RecordDayRatingUseCase().run(
            record: rated.record, rating: .ok, history: [],
            previous: rated.calibration, time: WowFixture.evening
        )
        #expect(again.record.feedback.filter { $0.dayRating != nil }.count == 1)
        #expect(again.record.rating == .ok)
    }

    // MARK: Деградация

    @Test("Без данных здоровья план всё равно строится, но без обещаний")
    func withoutHealthData() async throws {
        let output = await useCase(providers: [
            FakeContextProvider(id: .healthKit, signals: [], status: .indeterminate),
            NutritionContextProvider(profile: WowFixture.nutrition, meals: []),
        ]).run(
            PlanDayUseCase.Input(
                time: WowFixture.morning, tasks: WowFixture.tasks, goals: WowFixture.goals,
                profile: WowFixture.profile, nutrition: WowFixture.nutrition,
                history: [], calibration: .default
            )
        )
        let state = try #require(output.record.state)
        #expect(state.loadAdvice == .unknown)
        #expect(state.confidence == 0)

        let brief = try #require(output.record.plan?.brief)
        #expect(!brief.message.contains("обычн"))
        #expect(output.record.plan?.blocks.isEmpty == false)
    }

    @Test("Повторный проход дня не пересобирает принятый план")
    func acceptedPlanIsRevisedNotRebuilt() async throws {
        let built = await useCase(providers: providers).run(morningInput())
        let accepted = AcceptPlanUseCase(nudgeEngine: NudgeEngine(renderer: explainer))
            .run(record: built.record, calibration: .default, time: WowFixture.morning)

        let again = await useCase(providers: providers).run(morningInput(time: WowFixture.afternoon, existing: accepted.record))
        #expect(again.record.plan?.id == accepted.record.plan?.id)
        #expect(again.record.plan?.status == .accepted)
        #expect((again.record.plan?.version ?? 0) > (accepted.record.plan?.version ?? 0))
    }
}
