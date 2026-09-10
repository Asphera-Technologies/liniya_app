import Testing
import Foundation
@testable import LineaCore

@Suite("TaskScorer")
struct TaskScorerTests {
    private let scorer = TaskScorer()

    @Test("Все пять компонентов считаются по §7 и складываются в total")
    func components() {
        let time = WowFixture.morning
        let snapshot = WowFixture.snapshot(at: time)
        let state = PlanFixture.reducedState(at: time)
        let taskA = snapshot.tasks.first { $0.id == WowFixture.taskA }!

        let score = scorer.score(task: taskA, at: WowFixture.moment(9), windowMinutes: 240,
                                 snapshot: snapshot, state: state, time: time)

        // Дедлайн 12:00, оценка 90 мин → slack 1.5 ч → exp(−1.5/36).
        #expect(abs(score.urgency - exp(-1.5 / 36)) < 1e-9)
        // important (1.0) + недельная цель (+0.2) → cap 1.0.
        #expect(score.importance == 1.0)
        // Активная недельная цель, 4 дня до конца, прогресс 0.3.
        #expect(abs(score.goalAlignment - (0.6 + 0.3 + 0.1 * exp(-4.0 / 7)) * 0.91) < 1e-9)
        // capacity(09:00) = (0.5 + 0.5·0.38)·0.85; demand 0.9 → 1 − 1.5·gap.
        let capacity = (0.5 + 0.5 * 0.38) * 0.85
        #expect(abs((score.energyFit ?? -1) - (1 - 1.5 * (0.9 - capacity))) < 1e-9)
        #expect(score.durationFit == 1)
        #expect(score.total > 0.85 && score.total < 0.9)
    }

    @Test("Без данных о состоянии energyFit исключается, а его вес перераспределяется")
    func energyFitExcluded() {
        let time = WowFixture.morning
        let snapshot = WowFixture.snapshot(at: time)
        let task = snapshot.tasks.first { $0.id == WowFixture.taskC }!
        let unknown = PlanFixture.unknownState(at: time)

        let score = scorer.score(task: task, at: WowFixture.moment(9), windowMinutes: 240,
                                 snapshot: snapshot, state: unknown, time: time)

        #expect(score.energyFit == nil)
        let config = EngineConfig.default
        let weights = config.weightUrgency + config.weightImportance + config.weightGoalAlignment + config.weightDurationFit
        let expected = (score.urgency * config.weightUrgency
                        + score.importance * config.weightImportance
                        + score.goalAlignment * config.weightGoalAlignment
                        + score.durationFit * config.weightDurationFit) / weights
        #expect(abs(score.total - expected) < 1e-9)
    }

    @Test("Просроченный дедлайн даёт максимальную срочность, отсутствие дедлайна и дня — минимальную")
    func urgencyEdges() {
        let time = WowFixture.morning
        let snapshot = WowFixture.snapshot(at: time)
        let overdue = LineaTask(id: WowFixture.taskA, title: "Просрочено", date: WowFixture.today,
                                createdAt: WowFixture.created, deadline: WowFixture.moment(7), estimatedMinutes: 30)
        let floating = LineaTask(title: "Когда-нибудь", createdAt: WowFixture.created, estimatedMinutes: 30)

        #expect(scorer.urgency(task: overdue, plannedMinutes: 30, at: WowFixture.moment(9),
                               profile: snapshot.profile, time: time) == 1)
        #expect(scorer.urgency(task: floating, plannedMinutes: 30, at: WowFixture.moment(9),
                               profile: snapshot.profile, time: time) == TaskScorer.neutralUrgency)
    }

    @Test("durationFit: окно короче минимального блока обнуляет компонент")
    func durationFit() {
        let config = EngineConfig.default
        #expect(scorer.durationFit(plannedMinutes: 30, windowMinutes: 10, config: config) == 0)
        #expect(scorer.durationFit(plannedMinutes: 30, windowMinutes: 30, config: config) == 1)
        #expect(abs(scorer.durationFit(plannedMinutes: 120, windowMinutes: 60, config: config) - 0.3) < 1e-9)
    }

    @Test("estimateMultiplier растягивает планируемую длительность")
    func plannedDuration() {
        let task = LineaTask(title: "Задача", createdAt: WowFixture.created, estimatedMinutes: 60)
        var calibration = Calibration.default
        calibration.estimateMultiplier = 1.25
        #expect(PlanDuration.minutes(for: task, calibration: calibration) == 75)
        #expect(PlanDuration.minutes(for: task, calibration: .default) == 60)
    }
}

@Suite("FreeWindows")
struct FreeWindowsTests {
    @Test("Рабочий день минус обязательства wow-сценария")
    func wowWindows() {
        let time = WowFixture.morning
        let windows = FreeWindows.compute(
            day: WowFixture.today, now: time.now, profile: WowFixture.profile,
            commitments: WowFixture.defaultCommitments, time: time
        )
        let described = windows.map { "\(PlanFixture.hhmm($0.start))–\(PlanFixture.hhmm($0.end))" }
        #expect(described == ["09:00–13:00", "13:40–15:50", "16:20–17:00", "18:00–21:00"])
    }

    @Test("Окно начинается не раньше now и короткие огрызки отбрасываются")
    func startsAtNow() {
        let time = WowFixture.time(15, 45)
        let windows = FreeWindows.compute(
            day: WowFixture.today, now: time.now, profile: WowFixture.profile,
            commitments: WowFixture.defaultCommitments, time: time
        )
        // 15:45–15:50 — пять минут перед созвоном, это не окно.
        let described = windows.map { "\(PlanFixture.hhmm($0.start))–\(PlanFixture.hhmm($0.end))" }
        #expect(described == ["16:20–17:00", "18:00–21:00"])
    }

    @Test("После конца рабочего дня свободных окон нет")
    func afterWorkday() {
        let time = WowFixture.time(22, 0)
        let windows = FreeWindows.compute(
            day: WowFixture.today, now: time.now, profile: WowFixture.profile,
            commitments: WowFixture.defaultCommitments, time: time
        )
        #expect(windows.isEmpty)
    }
}
