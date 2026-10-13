//
//  AutoReschedule.swift
//  Linea
//
//  «Пусть Linea решит» (ADR-043): человек отдаёт выбор места задачи Linea.
//  Задача становится отложенной (`deferred`) до найденного окна, у неё
//  `reschedule_mode = automatic`, а движок сам ищет подходящее окно:
//    • не раньше чем через полтора часа — задачу только что отложили;
//    • до срока задачи, если он впереди, иначе — на две недели вперёд;
//    • день, где хватает свободного времени: рабочий день минус встречи из
//      календаря, еда, задачи со своим временем — и минус дела, которые на
//      этот день уже стоят;
//    • окно, куда задача помещается целиком; сложную — с утра, пока голова
//      свежая, лёгкую — после обеда, чтобы не занимать утро, если в этот
//      день есть такое место.
//  Окна нигде нет — день, когда ещё можно начать, а время найдёт план.
//
//  День и окно — решение Linea, а не человека: если день прошёл, а задача не
//  сделана, Linea сама найдёт новое окно (`replacingMissed`), без
//  «просрочено». Человек сам поставил день — выбор снова за ним
//  (`TaskOwnership.userEdited`).
//

import Foundation

/// Что Linea знает о ближайших днях, когда сама ищет задаче место.
nonisolated struct RescheduleContext: Sendable {
    let profile: UserProfile
    /// Задачи человека: что уже стоит на каждый день и у каких своё время.
    let tasks: [LineaTask]
    /// Встречи календаря на ближайшие дни и обязательства сегодняшнего дня.
    let commitments: [Commitment]
    /// Окна еды — на каждый день.
    let nutrition: NutritionProfile?
    let calibration: Calibration
    let config: EngineConfig
    let time: TimeContext

    init(
        profile: UserProfile,
        tasks: [LineaTask],
        commitments: [Commitment] = [],
        nutrition: NutritionProfile? = nil,
        calibration: Calibration = .default,
        config: EngineConfig = .default,
        time: TimeContext
    ) {
        self.profile = profile
        self.tasks = tasks
        self.commitments = commitments
        self.nutrition = nutrition
        self.calibration = calibration
        self.config = config
        self.time = time
    }

    /// Чем занят день: встречи, задачи со своим временем, еда. Повторы не
    /// страшны — занятое время объединяется (`FreeWindows`).
    func commitments(on day: Date) -> [Commitment] {
        let interval = time.dayInterval(containing: day)
        var result = commitments.filter { $0.interval.intersects(interval) }
        result += CommitmentMapper().commitments(signals: [], tasks: tasks, day: interval, time: time)
        for window in nutrition?.mealWindows ?? [] {
            let start = time.date(on: interval.start, at: window.start)
            result.append(Commitment(
                id: "meal-\(window.id)-\(Int(interval.start.timeIntervalSince1970))", title: window.kind.title,
                start: start, end: start.addingTimeInterval(TimeInterval(window.durationMinutes * 60)),
                kind: .meal, source: .nutrition
            ))
        }
        return result
    }

    /// Сколько минут дел уже стоит на этот день — кроме задачи `except` и
    /// задач со своим временем (они уже среди занятого).
    func assignedMinutes(on day: Date, except taskID: UUID) -> Int {
        tasks.filter { task in
            task.isOpen && task.id != taskID && !task.isFixed
                && (task.date.map { time.isSameDay($0, day) } ?? false)
        }
        .reduce(0) { $0 + PlanDuration.minutes(for: $1, calibration: calibration) }
    }
}

nonisolated struct AutoReschedule: Sendable {
    /// Задачу только что отложили — раньше Linea её не поставит.
    static let gapMinutes = TaskLifecycle.notNowMinutes
    /// Без срока Linea ищет место на столько дней вперёд.
    static let horizonDays = 14
    /// Утро кончается: сложное — до этого часа, лёгкое — после.
    static let morningEnd = TimeOfDay(hour: 13)

    /// Куда Linea ставит задачу.
    nonisolated struct Placement: Hashable, Sendable {
        let day: Date
        /// Начало окна, где задача помещается целиком; nil — такого окна
        /// нет, время найдёт план.
        let start: Date?
    }

    init() {}

    // MARK: Найти место

    /// Место задачи не раньше `earliest`.
    func place(_ task: LineaTask, notBefore earliest: Date, context: RescheduleContext) -> Placement {
        let time = context.time
        let needed = PlanDuration.minutes(for: task, calibration: context.calibration)
        let neededSeconds = TimeInterval(needed * 60)
        let firstDay = time.startOfDay(earliest)
        // Срок впереди ограничивает поиск; прошедший — уже нет.
        let deadline = task.deadline.flatMap { $0 > earliest ? $0 : nil }
        let lastDay = deadline.map { time.startOfDay($0) } ?? time.adding(days: Self.horizonDays - 1, to: firstDay)

        var fallback: Placement?
        var day = firstDay
        while day <= lastDay {
            let windows = FreeWindows.compute(day: day, now: earliest, profile: context.profile,
                                              commitments: context.commitments(on: day), config: context.config, time: time)
            let fitting = windows.filter { window in
                window.duration >= neededSeconds
                    && (deadline.map { window.start.addingTimeInterval(neededSeconds) <= $0 } ?? true)
            }
            if let window = choose(fitting, needed: neededSeconds, for: task.cognitiveDemand, day: day, time: time) {
                let free = Int(windows.reduce(0) { $0 + $1.duration } / 60)
                if free - context.assignedMinutes(on: day, except: task.id) >= needed {
                    return Placement(day: day, start: window.start)
                }
                // Окно есть, но день и так полон — запасной вариант.
                if fallback == nil { fallback = Placement(day: day, start: window.start) }
            }
            day = time.adding(days: 1, to: day)
        }
        if let fallback { return fallback }
        // Целиком не помещается нигде: день, когда ещё можно начать.
        let workdayEnd = time.date(on: firstDay, at: context.profile.workdayEnd)
        return Placement(day: earliest < workdayEnd ? firstDay : time.adding(days: 1, to: firstDay), start: nil)
    }

    /// Сложное — в первое утреннее окно дня, лёгкое — после обеда, если
    /// там есть место; иначе, и обычное, — в первое окно, где задача
    /// помещается.
    private func choose(_ windows: [DateInterval], needed: TimeInterval, for demand: CognitiveDemand,
                        day: Date, time: TimeContext) -> DateInterval? {
        let morningEnd = time.date(on: day, at: Self.morningEnd)
        switch demand {
        case .deep:
            return windows.first { $0.start < morningEnd } ?? windows.first
        case .light:
            let afternoon = windows.lazy.compactMap { window -> DateInterval? in
                let start = max(window.start, morningEnd)
                return window.end.timeIntervalSince(start) >= needed ? DateInterval(start: start, end: window.end) : nil
            }.first
            return afternoon ?? windows.first
        case .normal:
            return windows.first
        }
    }

    // MARK: Поставить

    /// Задача на найденном месте: отложена до окна, день и время — решение
    /// Linea (она может переставить их сама), режим — `automatic`.
    func applying(_ placement: Placement, to task: LineaTask, earliest: Date, time: TimeContext) -> LineaTask {
        var result = task
        result.date = placement.day
        result.scheduledStart = nil
        result.startedAt = nil
        if let start = placement.start {
            result.deferredUntil = start > time.now ? start : nil
        } else {
            result.deferredUntil = time.isSameDay(placement.day, earliest) && earliest > time.now ? earliest : nil
        }
        result.rescheduleMode = .automatic
        result.userFields = (task.userFields ?? Set(TaskField.allCases)).subtracting([.day, .startTime])
        // Из «Без даты» — уже разобрана: место ей нашла Linea.
        if task.date == nil, task.deadline == nil { result.inboxReviewedAt = time.now }
        return result
    }

    /// «Пусть Linea решит»: место не раньше чем через полтора часа.
    func decide(_ task: LineaTask, context: RescheduleContext) -> (task: LineaTask, placement: Placement) {
        let time = context.time
        let earliest = time.now.addingTimeInterval(TimeInterval(Self.gapMinutes * 60))
        let placement = place(task, notBefore: earliest, context: context)
        return (applying(placement, to: task, earliest: earliest, time: time), placement)
    }

    // MARK: День прошёл

    /// Задачи «Пусть Linea решит», чей день прошёл, а они не сделаны: Linea
    /// сама находит им новое окно — с этой минуты. Начатые не трогает.
    func replacingMissed(context: RescheduleContext) -> [LineaTask] {
        let time = context.time
        return context.tasks.compactMap { task in
            guard task.isOpen, task.rescheduleMode == .automatic, task.startedAt == nil,
                  let date = task.date, time.startOfDay(date) < time.today else { return nil }
            let placement = place(task, notBefore: time.now, context: context)
            return applying(placement, to: task, earliest: time.now, time: time)
        }
    }

    // MARK: Тексты

    /// «Поставила на завтра, 10:00.», «Поставила на чт, 16 окт, 10:00.»,
    /// окна нет — «Поставила на завтра — время найдёт план.»
    static func note(_ placement: Placement, time: TimeContext) -> String {
        let day = dayPhrase(placement.day, time: time)
        guard let start = placement.start else { return "Поставила на \(day) — время найдёт план." }
        return "Поставила на \(day), \(RussianText.clock(start, time: time))."
    }

    /// «сегодня», «завтра», «чт, 16 окт».
    static func dayPhrase(_ day: Date, time: TimeContext) -> String {
        if time.isSameDay(day, time.today) { return "сегодня" }
        if time.isSameDay(day, time.adding(days: 1, to: time.today)) { return "завтра" }
        return RussianText.shortDay(day, time: time).lowercased()
    }
}
