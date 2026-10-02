//
//  TaskReschedule.swift
//  Linea
//
//  «Перенести» у строки задачи: куда задачу можно перенести и что с ней при
//  этом станет. Слова те же, что у чипа «Когда» в быстром вводе (`TaskDay`):
//  сегодня, завтра, на неделе, на следующей неделе, свой день, без даты.
//
//  Задача переезжает целиком. Своё время — на тот же час нового дня. Срок,
//  который был в день задачи или остался бы позади нового дня, — тоже: иначе
//  перенесённая задача сразу стала бы просроченной и вернулась бы в сегодня.
//  Срок, который ещё впереди, остаётся: это обещание, а не день работы.
//  Перенос задачи, которую пора было делать, считает `PlanStore`
//  (`TaskDeferral`): Linea видит, что задача «зависает».
//

import Foundation

nonisolated struct TaskReschedule: Sendable {

    nonisolated enum Target: Hashable, Sendable {
        case today
        case tomorrow
        /// «На неделе»: без дня, к концу недели.
        case thisWeek
        /// Понедельник следующей недели.
        case nextWeek
        /// Свой день из календаря.
        case day(Date)
        /// «Без даты»: во входящие.
        case someday
    }

    /// Пункт выбора «Перенести»: «На следующей неделе · пн, 14 сен».
    nonisolated struct Option: Hashable, Sendable, Identifiable {
        let target: Target
        let title: String

        var id: String { title }
    }

    init() {}

    // MARK: Куда

    /// Варианты для задачи — кроме того, где она уже стоит. Закрытую задачу
    /// не переносят. «Выбрать дату…» экран добавляет сам.
    func options(for task: LineaTask, profile: UserProfile, time: TimeContext) -> [Option] {
        guard !task.isDone else { return [] }
        let today = time.today
        let tomorrow = time.adding(days: 1, to: today)
        let endOfWeek = TaskDay.endOfWeek(time: time, profile: profile)
        let nextMonday = TaskDay.nextMonday(time: time)
        let isOn: (Date) -> Bool = { day in task.date.map { time.isSameDay($0, day) } ?? false }
        let isThisWeek = task.date == nil && (task.deadline.map { time.isSameDay($0, endOfWeek) } ?? false)

        var options: [Option] = []
        if !isOn(today) {
            options.append(Option(target: .today, title: "Сегодня"))
        }
        if !isOn(tomorrow) {
            options.append(Option(target: .tomorrow, title: "Завтра"))
        }
        if !isThisWeek {
            let until = RussianText.shortDay(endOfWeek, time: time).lowercased()
            options.append(Option(target: .thisWeek, title: "На неделе · до \(until)"))
        }
        // В воскресенье следующая неделя начинается завтра — это уже «Завтра».
        if !time.isSameDay(nextMonday, tomorrow), !isOn(nextMonday) {
            let monday = RussianText.shortDay(nextMonday, time: time).lowercased()
            options.append(Option(target: .nextWeek, title: "На следующей неделе · \(monday)"))
        }
        if task.date != nil || task.deadline != nil {
            options.append(Option(target: .someday, title: "Без даты"))
        }
        return options
    }

    // MARK: Что станет с задачей

    func apply(_ target: Target, to task: LineaTask, profile: UserProfile, time: TimeContext) -> LineaTask {
        var task = task
        let wasInInbox = task.date == nil && task.deadline == nil
        switch target {
        case .today:
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
        }
        if wasInInbox { task.inboxReviewedAt = time.now }
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
}
