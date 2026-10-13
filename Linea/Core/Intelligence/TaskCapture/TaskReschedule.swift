//
//  TaskReschedule.swift
//  Linea
//
//  «Перенести» у строки задачи — свайпом или из меню (ADR-030, ADR-043):
//
//      Позже сегодня · Завтра · На неделе · Пусть Linea решит · Выбрать дату…
//
//  Здесь — какие варианты есть у задачи и что с ней станет. Слова те же, что
//  у чипа «Когда» в быстром вводе (`TaskDay`).
//
//  Задача переезжает целиком. Своё время — на тот же час нового дня. Срок,
//  который был в день задачи или остался бы позади нового дня, — тоже: иначе
//  перенесённая задача сразу стала бы просроченной и вернулась бы в сегодня.
//  Срок, который ещё впереди, остаётся: это обещание, а не день работы.
//  Начатая задача, которую переносят, больше не в работе. Перенос задачи,
//  которую пора было делать, считает `PlanStore` (`TaskDeferral`): Linea
//  видит, что задача «зависает».
//
//  «Позже сегодня» — день остаётся сегодняшним, а час Linea находит сама:
//  первое окно не раньше чем через полтора часа, где задача помещается
//  целиком; своё время у задачи снимается. «Пусть Linea решит» — и день, и окно выбирает Linea
//  (`AutoReschedule`), и переставляет сама, если день прошёл.
//

import Foundation

nonisolated struct TaskReschedule: Sendable {

    nonisolated enum Target: Hashable, Sendable {
        /// «Позже сегодня»: сегодня, в окно позже, которое найдёт Linea.
        case laterToday
        /// «Сегодня» — у задачи на другой день вместо «Позже сегодня».
        case today
        case tomorrow
        /// «На неделе»: без дня, к концу недели.
        case thisWeek
        /// Понедельник следующей недели. В меню больше нет — есть «Выбрать дату…».
        case nextWeek
        /// Свой день из календаря.
        case day(Date)
        /// «Без даты»: во входящие. В меню больше нет — есть карточка задачи.
        case someday
        /// «Пусть Linea решит» (`reschedule_mode = automatic`).
        case automatic
    }

    /// Пункт выбора «Перенести»: «На неделе · до вс, 13 сен».
    nonisolated struct Option: Hashable, Sendable, Identifiable {
        let target: Target
        let title: String

        var id: String { title }
    }

    /// Что стало с задачей — и что Linea скажет одной строкой.
    nonisolated struct Result: Sendable {
        let task: LineaTask
        /// «Перенесла на 14:30.», «Поставила на завтра, 10:00.»
        let note: String
    }

    init() {}

    // MARK: Куда

    /// Варианты для задачи по порядку постановки — кроме того, где она уже
    /// стоит. Закрытую задачу не переносят. «Выбрать дату…» экран добавляет
    /// сам.
    func options(for task: LineaTask, profile: UserProfile, time: TimeContext) -> [Option] {
        guard task.isOpen else { return [] }
        let today = time.today
        let tomorrow = time.adding(days: 1, to: today)
        let endOfWeek = TaskDay.endOfWeek(time: time, profile: profile)
        let isOn: (Date) -> Bool = { day in task.date.map { time.isSameDay($0, day) } ?? false }
        let isLater = task.date.map { time.startOfDay($0) > today } ?? false
        let isThisWeek = task.date == nil && (task.deadline.map { time.isSameDay($0, endOfWeek) } ?? false)

        var options: [Option] = []
        if isLater {
            // Задача на другой день — её можно вернуть в сегодня.
            options.append(Option(target: .today, title: "Сегодня"))
        } else if Self.laterTodayStart(time: time) < time.date(on: today, at: profile.workdayEnd) {
            options.append(Option(target: .laterToday, title: "Позже сегодня"))
        }
        if !isOn(tomorrow) {
            options.append(Option(target: .tomorrow, title: "Завтра"))
        }
        if !isThisWeek {
            let until = RussianText.shortDay(endOfWeek, time: time).lowercased()
            options.append(Option(target: .thisWeek, title: "На неделе · до \(until)"))
        }
        options.append(Option(target: .automatic, title: "Пусть Linea решит"))
        return options
    }

    // MARK: Что станет с задачей

    /// Перенос с тем, что Linea знает о ближайших днях: «Позже сегодня» и
    /// «Пусть Linea решит» ищут окно сами.
    func apply(_ target: Target, to task: LineaTask, context: RescheduleContext) -> Result {
        let time = context.time
        switch target {
        case .automatic:
            let decided = AutoReschedule().decide(task, context: context)
            return Result(task: decided.task, note: AutoReschedule.note(decided.placement, time: time))
        case .laterToday:
            var moved = moving(task, to: .today, profile: context.profile, time: time)
            // Своё время больше не держит задачу: она — позже.
            moved.scheduledStart = nil
            let earliest = Self.laterTodayStart(time: time)
            let fit = WindowFinder.nextFit(
                minutes: PlanDuration.minutes(for: task, calibration: context.calibration), on: time.today,
                notBefore: earliest, profile: context.profile,
                commitments: context.commitments(on: time.today, except: task.id),
                config: context.config, time: time
            )
            let start = fit?.start ?? earliest
            moved.deferredUntil = start
            moved.rescheduleMode = .laterToday
            return Result(task: moved, note: "Перенесла на \(RussianText.clock(start, time: time)).")
        default:
            let moved = moving(task, to: target, profile: context.profile, time: time)
            return Result(task: moved, note: note(for: target, task: moved, time: time))
        }
    }

    /// Перенос без знания о ближайших днях — день, срок и время по правилу.
    func apply(_ target: Target, to task: LineaTask, profile: UserProfile, time: TimeContext) -> LineaTask {
        apply(target, to: task, context: RescheduleContext(profile: profile, tasks: [task], time: time)).task
    }

    /// День, срок и время задачи для переноса, который выбрал человек:
    /// место снова выбирает он (`reschedule_mode` снят), «Не сейчас» и «в
    /// работе» — тоже.
    private func moving(_ task: LineaTask, to target: Target, profile: UserProfile, time: TimeContext) -> LineaTask {
        var task = task
        let wasInInbox = task.date == nil && task.deadline == nil
        switch target {
        case .today, .laterToday:
            move(&task, to: time.today, time: time)
        case .tomorrow:
            move(&task, to: time.adding(days: 1, to: time.today), time: time)
        case .nextWeek:
            move(&task, to: TaskDay.nextMonday(time: time), time: time)
        case .day(let day):
            move(&task, to: time.startOfDay(day), time: time)
        case .thisWeek:
            let endOfWeek = TaskDay.endOfWeek(time: time, profile: profile)
            // Свой срок, который ещё впереди и раньше конца недели, остаётся.
            let keepsDeadline = task.deadline.map { deadline in
                deadline > time.now && deadline < endOfWeek
                    && !(task.date.map { time.isSameDay($0, deadline) } ?? false)
            } ?? false
            task.date = nil
            task.scheduledStart = nil
            if !keepsDeadline { task.deadline = endOfWeek }
        case .someday:
            task.date = nil
            task.deadline = nil
            task.scheduledStart = nil
            // Человек сам решил «без даты» — разбирать её снова незачем.
            task.inboxReviewedAt = time.now
        case .automatic:
            break
        }
        if wasInInbox { task.inboxReviewedAt = time.now }
        task.rescheduleMode = nil
        task.deferredUntil = nil
        task.startedAt = nil
        return task
    }

    /// Задача на другой день: время — на тот же час, срок — если он был в
    /// день задачи или раньше нового дня.
    private func move(_ task: inout LineaTask, to day: Date, time: TimeContext) {
        let previousDay = task.date
        if let start = task.scheduledStart {
            task.scheduledStart = time.date(on: day, at: time.timeOfDay(of: start))
        }
        if let deadline = task.deadline {
            let wasOnTaskDay = previousDay.map { time.isSameDay($0, deadline) } ?? false
            if wasOnTaskDay || deadline < day {
                task.deadline = time.date(on: day, at: time.timeOfDay(of: deadline))
            }
        }
        task.date = day
    }

    /// «Позже сегодня» — не раньше чем через полтора часа, как «Не сейчас».
    static func laterTodayStart(time: TimeContext) -> Date {
        time.now.addingTimeInterval(TimeInterval(TaskLifecycle.notNowMinutes * 60))
    }

    // MARK: Что сказать

    /// «Перенесла на завтра.», «Перенесла на эту неделю — до вс, 13 сен.»
    private func note(for target: Target, task: LineaTask, time: TimeContext) -> String {
        switch target {
        case .thisWeek:
            let until = task.deadline.map { " — до " + RussianText.shortDay($0, time: time).lowercased() } ?? ""
            return "Перенесла на эту неделю\(until)."
        case .someday:
            return "Перенесла в «Без даты»."
        case .nextWeek:
            return "Перенесла на следующую неделю."
        default:
            guard let day = task.date else { return "Перенесла." }
            return "Перенесла на \(AutoReschedule.dayPhrase(day, time: time))."
        }
    }
}
