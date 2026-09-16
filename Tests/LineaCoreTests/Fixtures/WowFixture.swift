//
//  WowFixture.swift
//  LineaCoreTests
//
//  The wow-scenario from the brief as concrete, deterministic data:
//  Europe/Moscow, Wednesday 2026-09-09. Slept 6:03 (usual 7:13), HRV 38 ms
//  (usual 52), resting HR 58 (usual 54). Tasks A/B/C, goal «Запустить MVP
//  Linea», lunch 13:00–13:40, call 15:50–16:20, workout 17:00–18:00 — so the
//  nudge at 14:30 really has «1 ч 20 мин» until the next commitment.
//

import Foundation
@testable import LineaCore

nonisolated enum WowFixture {
    static let timeZoneID = "Europe/Moscow"

    // MARK: Time

    static func time(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> TimeContext {
        TimeContext(now: moment(hour, minute, dayOffset: dayOffset), timeZoneIdentifier: timeZoneID)
    }

    static let morning = time(8, 0)
    static let afternoon = time(14, 30)
    static let evening = time(21, 0)

    /// 2026-09-09 at the given local time (Moscow), shifted by whole days.
    static func moment(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 9 + dayOffset
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID)!
        calendar.locale = Locale(identifier: "ru_RU")
        calendar.firstWeekday = 2
        return calendar
    }

    static var today: Date { calendar.startOfDay(for: moment(12)) }
    static var todayInterval: DateInterval { morning.dayInterval(containing: today) }

    // MARK: IDs (stable across runs)

    static let taskA = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    static let taskB = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!
    static let taskC = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000003")!
    static let taskCall = UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000004")!
    static let taskWorkout = UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000005")!
    static let goalMVP = UUID(uuidString: "99999999-0000-0000-0000-000000000009")!
    static let snapshotID = UUID(uuidString: "55555555-0000-0000-0000-000000000005")!
    static let planID = UUID(uuidString: "77777777-0000-0000-0000-000000000007")!

    // MARK: Tasks & goals

    static let created = moment(9, 0, dayOffset: -2)

    static var tasks: [LineaTask] {
        [
            LineaTask(id: taskA, title: "Презентация КП", date: today, priority: .important, createdAt: created,
                      deadline: moment(12), estimatedMinutes: 90, cognitiveDemand: .deep, goalID: goalMVP),
            LineaTask(id: taskB, title: "Разработка Linea", date: today, priority: .normal, createdAt: created.addingTimeInterval(60),
                      estimatedMinutes: 120, cognitiveDemand: .deep, goalID: goalMVP),
            LineaTask(id: taskC, title: "Ответить на письма", date: today, priority: .normal, createdAt: created.addingTimeInterval(120),
                      estimatedMinutes: 30, cognitiveDemand: .light),
            LineaTask(id: taskCall, title: "Созвон с командой", date: today, priority: .normal, createdAt: created.addingTimeInterval(180),
                      scheduledStart: moment(15, 50), estimatedMinutes: 30, cognitiveDemand: .normal),
            LineaTask(id: taskWorkout, title: "Тренировка", date: today, priority: .normal, createdAt: created.addingTimeInterval(240),
                      scheduledStart: moment(17), estimatedMinutes: 60, cognitiveDemand: .light),
        ]
    }

    static var goals: [LineaGoal] {
        // Цель со сроком в конце недели: «Запустить MVP Linea» к воскресенью.
        [LineaGoal(id: goalMVP, title: "Запустить MVP Linea", progress: 0.3, createdAt: created,
                   startDate: moment(0, 0, dayOffset: -2), endDate: moment(0, 0, dayOffset: 4))]
    }

    static let profile = UserProfile()

    static let nutrition = NutritionProfile(
        excludedProducts: ["сахар"],
        preferredProducts: ["овсянка", "курица", "овощи", "рыба"],
        mealWindows: [MealWindow(kind: .lunch, start: TimeOfDay(hour: 13), durationMinutes: 40)]
    )

    // MARK: Signals for today (HealthKit)

    /// Last night from the Watch, with stages: asleep = 6:03 = 21 780 s.
    static var sleepSignalsWatch: [ContextSignal] {
        let src = "com.apple.health.watch"
        func seg(_ stage: SleepStage, _ sh: Int, _ sm: Int, _ eh: Int, _ em: Int) -> ContextSignal {
            ContextSignal(kind: .sleepSegment, value: .interval(nil), start: moment(sh, sm), end: moment(eh, em),
                          source: .healthKit, attributes: [SignalAttribute.stage: stage.rawValue, SignalAttribute.sourceBundle: src])
        }
        return [
            seg(.inBed, 0, 40, 7, 20),
            seg(.core, 0, 57, 2, 30),
            seg(.deep, 2, 30, 3, 20),
            seg(.awake, 3, 20, 3, 32),
            seg(.rem, 3, 32, 4, 30),
            seg(.core, 4, 30, 6, 12),
            seg(.rem, 6, 12, 7, 12),
        ]
    }

    /// The same night as the iPhone sees it (inBed only) — must NOT be double counted.
    static var sleepSignalsPhone: [ContextSignal] {
        [ContextSignal(kind: .sleepSegment, value: .interval(nil), start: moment(0, 30), end: moment(7, 30),
                       source: .healthKit, attributes: [SignalAttribute.stage: SleepStage.inBed.rawValue,
                                                        SignalAttribute.sourceBundle: "com.apple.Health"])]
    }

    static var hrvSignals: [ContextSignal] {
        [(2, 10, 36.0), (4, 0, 40.0), (6, 30, 38.0)].map { h, m, v in
            ContextSignal(kind: .hrvSDNN, value: .number(v), start: moment(h, m), source: .healthKit, unit: "ms")
        }
    }

    static var restingHRSignal: ContextSignal {
        ContextSignal(kind: .restingHeartRate, value: .number(58), start: moment(7, 30), source: .healthKit, unit: "bpm")
    }

    static var stepsSignal: ContextSignal {
        ContextSignal(kind: .steps, value: .number(420), start: today, end: moment(8), source: .healthKit, unit: "count")
    }

    static var healthSignals: [ContextSignal] {
        sleepSignalsWatch + sleepSignalsPhone + hrvSignals + [restingHRSignal, stepsSignal]
    }

    // MARK: History (28 days before today)

    /// Usual sleep 7:13 (25 980 s), HRV 52 ms, resting HR 54, a 45-min workout every third day.
    static var history: [DailyHealthSummary] {
        let sleepPattern: [Double] = [0, 600, -900, 300, -1200, 0, 1500]
        let hrvPattern: [Double] = [0, 0.06, -0.08, 0.03, -0.11, 0, 0.09]
        let rhrPattern: [Double] = [0, 1, -1, 2, -2, 0, 1]
        return (1...28).reversed().map { i in
            let day = calendar.date(byAdding: .day, value: -i, to: today)!
            var values: [SignalKind: Double] = [
                .sleepAsleep: 25_980 + sleepPattern[i % 7],
                .sleepInBed: 28_200 + sleepPattern[i % 7],
                .sleepBedtime: 57 + sleepPattern[i % 7] / 120,   // ≈ 00:57
                .hrvLog: log(52) + hrvPattern[i % 7],
                .restingHeartRate: 54 + rhrPattern[i % 7],
                .steps: 8_000 + Double(i % 5) * 400,
                .activeEnergy: 520 + Double(i % 3) * 60,
            ]
            if i % 3 == 0 { values[.workoutMinutes] = 45 }
            return DailyHealthSummary(day: day, values: values)
        }
    }

    // MARK: Snapshot

    static func snapshot(at time: TimeContext = morning, signals: [ContextSignal]? = nil, commitments: [Commitment]? = nil) -> ContextSnapshot {
        ContextSnapshot(
            id: snapshotID,
            day: today,
            capturedAt: time.now,
            timeZoneIdentifier: timeZoneID,
            signals: signals ?? healthSignals,
            providerStatuses: [.healthKit: .ready, .nutrition: .ready],
            tasks: tasks,
            goals: goals,
            commitments: commitments ?? defaultCommitments,
            profile: profile,
            nutrition: nutrition,
            meals: []
        )
    }

    /// Lunch window + the two fixed tasks (what CommitmentMapper would produce).
    static var defaultCommitments: [Commitment] {
        [
            Commitment(id: "meal-lunch", title: "Обед", start: moment(13), end: moment(13, 40), kind: .meal, source: .nutrition),
            Commitment(id: "task-\(taskCall.uuidString)", title: "Созвон с командой", start: moment(15, 50), end: moment(16, 20), kind: .task, source: .tasks, taskID: taskCall),
            Commitment(id: "task-\(taskWorkout.uuidString)", title: "Тренировка", start: moment(17), end: moment(18), kind: .workout, source: .tasks, taskID: taskWorkout),
        ]
    }
}
