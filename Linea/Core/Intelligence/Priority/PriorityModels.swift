//
//  PriorityModels.swift
//  Linea
//
//  Входы и ответ движка приоритизации (Docs/intelligence.md §16). Вместо
//  одного общего балла у задачи две оценки:
//    • importance — насколько задача важна вообще;
//    • action — насколько разумно взяться за неё прямо сейчас.
//  «Подготовить стратегию» на полтора часа важна всегда, но за 20 минут до
//  встречи браться за неё неразумно; после встречи — снова да.
//

import Foundation

/// Что уже сделано сегодня до этой минуты (`recent_execution`): от этого
/// зависит ритм — продолжать начатую цель легче, после долгой сложной работы
/// труднее, а третья подряд задача одного типа тянет слабее.
nonisolated struct RecentExecution: Hashable, Sendable {
    nonisolated struct Done: Hashable, Sendable {
        let taskID: UUID
        let kind: TaskKind
        let goalID: UUID?
        let minutes: Int
        let isDeep: Bool
        let completedAt: Date
    }

    /// Закрытое сегодня, по времени.
    let doneToday: [Done]

    init(doneToday: [Done] = []) {
        self.doneToday = doneToday.sorted { $0.completedAt < $1.completedAt }
    }

    /// Из задач: всё, что закрыто сегодня не позже `time.now`.
    static func today(from tasks: [LineaTask], time: TimeContext, classifier: TaskClassifier = TaskClassifier()) -> RecentExecution {
        let day = time.dayInterval(containing: time.now)
        let done = tasks.compactMap { task -> Done? in
            guard task.isDone, let at = task.completedAt, day.contains(at), at <= time.now else { return nil }
            return Done(
                taskID: task.id,
                kind: classifier.kind(of: task),
                goalID: task.goalID,
                minutes: TaskEstimate.minutes(for: task, classifier: classifier),
                isDeep: task.cognitiveDemand.score >= DecisionEngine.deepDemandThreshold,
                completedAt: at
            )
        }
        return RecentExecution(doneToday: done)
    }

    /// Минут сложной работы, закрытой до этого момента.
    func deepMinutes(before moment: Date) -> Int {
        doneToday.filter { $0.isDeep && $0.completedAt <= moment }.reduce(0) { $0 + $1.minutes }
    }

    /// Сколько задач этого типа закрыто до этого момента.
    func count(of kind: TaskKind, before moment: Date) -> Int {
        doneToday.filter { $0.kind == kind && $0.completedAt <= moment }.count
    }

    /// Последняя закрытая задача, если её закрыли не раньше `minutes` назад.
    func last(before moment: Date, within minutes: Int) -> Done? {
        guard let last = doneToday.last(where: { $0.completedAt <= moment }) else { return nil }
        return moment.timeIntervalSince(last.completedAt) <= TimeInterval(minutes * 60) ? last : nil
    }
}

/// Из чего сложилась важность. Все — 0…1.
nonisolated struct ImportanceFactors: Codable, Hashable, Sendable {
    /// Приоритет, который поставил человек (`user_priority`).
    var priority: Double
    /// Цель: её важность и срок (`goal_importance`, `goal_deadline`). Без
    /// цели — 0, и в важность она не входит: задача оценивается по своим
    /// признакам (`PriorityEngine.importance`).
    var goal: Double
    /// Срок задачи и просрочка (`deadline`, `overdue`).
    var deadline: Double
    /// Тип задачи (`task_type`).
    var kind: Double
    /// Сколько задач ждут эту (`dependencies`).
    var dependents: Double
    /// Сколько раз задачу переносили (`number_of_deferrals`).
    var deferrals: Double
}

/// Из чего сложилась уместность «сейчас». Все — 0…1.
nonisolated struct ActionFactors: Codable, Hashable, Sendable {
    /// Хватает ли окна до следующего дела (`available_window` против `estimated_duration`).
    var window: Double
    /// Хватает ли сил на такую сложность в этот час (`current_state`);
    /// nil — состояние неизвестно, и оно не учитывается.
    var energy: Double?
    /// Поджимает ли срок прямо сейчас.
    var deadline: Double
    /// Задача на сегодня (или просрочена), без дня или на другой день (`daily_context`).
    var day: Double
    /// Ритм: продолжать ту же цель легче, после долгой сложной работы — труднее.
    var rhythm: Double
    /// Баланс типов за день: ещё одна задача уже сделанного типа тянет слабее.
    var balance: Double
    /// 0 — сейчас нельзя вовсе: ждёт другую задачу, у неё своё время, сейчас занято.
    var gate: Double
}

/// Почему сейчас не лучшее время для задачи.
nonisolated enum ActionLimit: Codable, Hashable, Sendable {
    /// Ждёт задачу, которая ещё не закрыта.
    case blocked(by: UUID)
    /// Окно до следующего дела короче, чем нужно задаче.
    case shortWindow(minutesLeft: Int, minutesNeeded: Int)
    /// Сейчас занято (встреча, обед) или рабочий день кончился.
    case busy
    /// У задачи назначено время, и оно не сейчас.
    case fixedTime(Date)
    /// Задача запланирована на другой день.
    case plannedLater(Date)
    /// Сил сейчас мало для такой сложной задачи.
    case lowEnergy

    var isShortWindow: Bool {
        if case .shortWindow = self { return true }
        return false
    }
}

/// Оценка одной задачи в один момент.
nonisolated struct PriorityAssessment: Hashable, Sendable {
    let taskID: UUID
    let kind: TaskKind
    /// «Насколько задача важна вообще», 0…1.
    let importance: Double
    /// «Насколько разумно браться сейчас», 0…1.
    let action: Double
    let importanceFactors: ImportanceFactors
    let actionFactors: ActionFactors
    let limits: [ActionLimit]
    /// Сколько минут нужно задаче — с поправкой калибровки.
    let minutesNeeded: Int
    /// Сколько минут до следующего дела.
    let minutesAvailable: Int
    /// То же для блока плана — с пятью факторами брифа.
    let breakdown: ScoreBreakdown

    /// Что сравнивает планировщик: важное, за которое разумно браться сейчас.
    var focus: Double { importance * action }
}

/// Окно с этого момента: до ближайшего обязательства или до конца рабочего дня.
nonisolated struct PriorityWindow: Hashable, Sendable {
    let minutes: Int
    /// Обязательство, которым кончается окно; nil — конец рабочего дня.
    let until: Commitment?
    /// Сейчас занято: идёт обязательство или рабочий день кончился.
    let isBusy: Bool
}

/// Всё, что движок видит: задачи, цели и календарь (снимок), состояние,
/// время, сделанное сегодня и зависимости между задачами.
nonisolated struct PriorityContext: Sendable {
    /// Задачи, цели, обязательства (календарь, еда, задачи со временем), профиль.
    let snapshot: ContextSnapshot
    /// `current_state`: энергия и уверенность в ней.
    let state: UserState
    let calibration: Calibration
    let config: EngineConfig
    /// `current_time`.
    let time: TimeContext
    let recent: RecentExecution
    let dependencies: TaskDependencies

    init(
        snapshot: ContextSnapshot,
        state: UserState,
        calibration: Calibration = .default,
        config: EngineConfig = .default,
        time: TimeContext,
        recent: RecentExecution? = nil
    ) {
        self.snapshot = snapshot
        self.state = state
        self.calibration = calibration
        self.config = config
        self.time = time
        self.recent = recent ?? RecentExecution.today(from: snapshot.tasks, time: time)
        self.dependencies = TaskDependencies(tasks: snapshot.tasks)
    }

    var profile: UserProfile { snapshot.profile }

    /// `free_windows` в одной точке: сколько минут с этого момента до
    /// ближайшего обязательства или конца рабочего дня. Обязательство самой
    /// задачи (`excluding`) окно не закрывает.
    func window(at moment: Date, excluding taskID: UUID? = nil) -> PriorityWindow {
        let workdayEnd = time.date(on: time.startOfDay(moment), at: profile.workdayEnd)
        guard moment < workdayEnd else { return PriorityWindow(minutes: 0, until: nil, isBusy: true) }
        let commitments = snapshot.commitments.filter { taskID == nil || $0.taskID != taskID }
        if let current = commitments.first(where: { $0.start <= moment && moment < $0.end }) {
            return PriorityWindow(minutes: 0, until: current, isBusy: true)
        }
        let next = commitments
            .filter { $0.start > moment && $0.start < workdayEnd }
            .min { lhs, rhs in lhs.start == rhs.start ? lhs.id < rhs.id : lhs.start < rhs.start }
        let end = next?.start ?? workdayEnd
        return PriorityWindow(minutes: Int(end.timeIntervalSince(moment) / 60), until: next, isBusy: false)
    }
}
