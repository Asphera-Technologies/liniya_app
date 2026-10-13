//
//  NotNowFeedback.swift
//  Linea
//
//  «Не сейчас» — главная обратная связь (ADR-042). Linea убирает
//  предложение, подбирает следующее («Хорошо, подберу другое.») и иногда
//  спрашивает, почему:
//
//      Почему не сейчас?
//      [Нет времени] [Нет сил] [Не хочется] [Неактуально]
//
//  Не при каждом отказе — только когда ответ поможет планировать:
//    • причина не видна по данным: окна хватает и сил, по данным, тоже —
//      иначе Linea и так знает, почему;
//    • ответ что-то поменяет: задача важная (высокий приоритет, важная цель,
//      срок сегодня или завтра), её уже откладывали или человек за неё уже
//      брался;
//    • и не часто: не больше трёх вопросов в день, не чаще раза в два часа,
//      про одну задачу — раз в день; два вопроса остались без ответа — до
//      завтра Linea не спрашивает.
//
//  Каждый ответ меняет план:
//    • «Нет времени» — вернуться не раньше чем через два часа, в первое окно,
//      где задача поместится целиком; сегодня такого нет — завтра;
//    • «Нет сил» — два часа Linea предлагает полегче: сложное — только если
//      больше нечего (`NextActionUseCase`);
//    • «Не хочется» — как без ответа: полтора часа, но ответ записан;
//    • «Неактуально» — задача уходит из планов, рядом «Вернуть».
//
//  Тон — без упрёка: не «ты снова отложил задачу», а что Linea сделает дальше.
//

import Foundation

nonisolated struct NotNowFeedback: Sendable {
    /// Не больше стольких вопросов в день.
    static let maxQuestionsPerDay = 3
    /// Между вопросами — не меньше.
    static let questionGapMinutes = 120
    /// Столько вопросов без ответа — и до завтра Linea не спрашивает.
    static let maxUnanswered = 2
    /// «Нет сил»: столько Linea предлагает полегче.
    static let lowEnergyMinutes = 120
    /// «Нет времени»: раньше этого Linea к задаче не вернётся.
    static let noTimeGapMinutes = 120

    let config: EngineConfig
    private let engine: PriorityEngine
    private let lifecycle = TaskLifecycle()

    init(config: EngineConfig = .default) {
        self.config = config
        self.engine = PriorityEngine(config: config)
    }

    // MARK: Спросить ли

    /// Вопрос «Почему не сейчас?» — или nil, если спрашивать незачем. Решается
    /// до того, как задачу отложили: по тому, как Linea видела её в этот момент.
    func question(
        for task: LineaTask,
        record: DayRecord?,
        tasks: [LineaTask],
        calibration: Calibration,
        time: TimeContext
    ) -> NotNowQuestion? {
        guard task.isOpen, let record, time.isSameDay(record.day, time.now) else { return nil }

        // Не часто.
        let asked = record.notNowQuestions.filter { $0.at <= time.now }
        guard asked.count < Self.maxQuestionsPerDay else { return nil }
        if let last = asked.map(\.at).max(),
           time.now.timeIntervalSince(last) < TimeInterval(Self.questionGapMinutes * 60) { return nil }
        guard !asked.contains(where: { $0.taskID == task.id }) else { return nil }
        let answered = Set(record.notNowAnswers.map(\.answer.taskID))
        guard asked.filter({ !answered.contains($0.taskID) }).count < Self.maxUnanswered else { return nil }

        // Причина и так видна: окна не хватает или сил на такое мало.
        if let assessment = assessment(of: task, record: record, tasks: tasks, calibration: calibration, time: time),
           assessment.limits.contains(where: { $0.isShortWindow || $0 == .lowEnergy }) {
            return nil
        }
        // Ответ ничего не поменяет — не спрашиваем.
        guard matters(task, record: record, time: time) else { return nil }

        let wasStarted = task.startedAt != nil
        let open = SuggestionLog.open(in: record)
        return NotNowQuestion(
            taskID: task.id,
            title: wasStarted ? "Что помешало?" : "Почему не сейчас?",
            wasStarted: wasStarted,
            suggestionID: open?.taskID == task.id ? open?.id : nil
        )
    }

    /// Ответ поможет планировать: задача важная, её уже откладывали или за
    /// неё уже брались.
    func matters(_ task: LineaTask, record: DayRecord, time: TimeContext) -> Bool {
        if task.startedAt != nil || task.priority == .important || task.deferralCount > 0 { return true }
        if let goalID = task.goalID,
           GoalBalance.importantGoals(record.snapshot?.goals ?? []).contains(where: { $0.id == goalID }) {
            return true
        }
        let endOfTomorrow = time.adding(days: 2, to: time.today)
        if let deadline = task.deadline, deadline < endOfTomorrow { return true }
        if let date = task.date, time.startOfDay(date) < time.today { return true }
        // Сегодня от неё уже отказывались.
        return record.feedback.contains { item in
            if case .taskNotNow(let taskID, _, _) = item.kind { return taskID == task.id && item.at < time.now }
            return false
        }
    }

    /// Как Linea видит задачу в эту минуту — так же, как «Сейчас».
    private func assessment(
        of task: LineaTask,
        record: DayRecord,
        tasks: [LineaTask],
        calibration: Calibration,
        time: TimeContext
    ) -> PriorityAssessment? {
        guard var snapshot = record.snapshot, let state = record.state else { return nil }
        snapshot.tasks = tasks
        let context = PriorityContext(snapshot: snapshot, state: state, calibration: calibration, config: config, time: time)
        return engine.assess(task, context: context)
    }

    // MARK: Ответ

    /// Что стало после ответа.
    nonisolated struct Outcome: Sendable {
        /// Задача: позже вернуться, убрать из планов — или как была.
        let task: LineaTask
        /// День с ответом; nil — записи дня нет.
        let record: DayRecord?
        /// Что Linea отвечает: «Хорошо, вернусь к ней в 14:30.»
        let reply: String
        /// «Неактуально» убрало задачу из планов — её можно вернуть.
        let canUndo: Bool
    }

    /// Ответ человека: задача и день меняются по причине.
    func answer(
        _ reason: NotNowReason,
        to question: NotNowQuestion,
        task: LineaTask,
        record: DayRecord?,
        calibration: Calibration,
        time: TimeContext
    ) -> Outcome {
        var updated = task
        var cancelled = false
        let reply: String
        switch reason {
        case .noTime:
            let back = noTimeReturn(for: task, record: record, calibration: calibration, time: time)
            updated.deferredUntil = max(task.deferredUntil ?? time.now, back.at)
            reply = back.isToday
                ? "Хорошо, вернусь к ней в \(RussianText.clock(back.at, time: time))."
                : "Хорошо, вернусь к ней завтра."
        case .noEnergy:
            reply = "Хорошо, пока предложу что-то полегче."
        case .unwilling:
            reply = "Хорошо, вернусь к ней позже."
        case .irrelevant:
            if let removed = lifecycle.cancel(task, at: time.now) {
                updated = removed
                cancelled = true
            }
            reply = "Убрала из планов."
        }
        let answer = NotNowAnswer(taskID: task.id, reason: reason, suggestionID: question.suggestionID,
                                  wasStarted: question.wasStarted)
        let day = record.map { day -> DayRecord in
            var day = day.appendingFeedback(.notNowReason(answer), at: time.now)
            if cancelled { day = day.appendingFeedback(.taskCancelled(taskID: task.id), at: time.now) }
            return day
        }
        return Outcome(task: updated, record: day, reply: reply, canUndo: cancelled)
    }

    /// Linea спросила — отметка в дне, чтобы не спрашивать часто.
    func asking(_ question: NotNowQuestion, in record: DayRecord, at moment: Date) -> DayRecord {
        record.appendingFeedback(.notNowAsked(taskID: question.taskID), at: moment)
    }

    /// «Вернуть» после «Неактуально»: задача снова в планах, в дне — отметка.
    func undo(_ task: LineaTask, record: DayRecord?, time: TimeContext) -> (task: LineaTask, record: DayRecord?)? {
        guard let restored = lifecycle.restore(task) else { return nil }
        return (restored, record.map { $0.appendingFeedback(.taskRestored(taskID: task.id), at: time.now) })
    }

    /// «Нет времени»: не раньше чем через два часа — в первое окно, где
    /// задача помещается целиком (встречи, еда и задачи со временем — из дня);
    /// сегодня такого нет — завтра с начала рабочего дня.
    func noTimeReturn(for task: LineaTask, record: DayRecord?, calibration: Calibration, time: TimeContext) -> (at: Date, isToday: Bool) {
        let profile = record?.snapshot?.profile ?? .default
        let commitments = (record?.snapshot?.commitments ?? []).filter { $0.taskID != task.id }
        let earliest = time.now.addingTimeInterval(TimeInterval(Self.noTimeGapMinutes * 60))
        if let fit = WindowFinder.nextFit(
            minutes: PlanDuration.minutes(for: task, calibration: calibration), on: time.today, notBefore: earliest,
            profile: profile, commitments: commitments, config: config, time: time
        ) {
            return (fit.start, true)
        }
        return (time.date(on: time.adding(days: 1, to: time.today), at: profile.workdayStart), false)
    }
}

nonisolated extension UserState {
    /// Человек сказал «Нет сил» — это вернее любых датчиков: сил мало, и
    /// Linea в этом уверена.
    func reportedTired() -> UserState {
        UserState(day: day, computedAt: computedAt, components: components, energy: 0, confidence: 1,
                  loadAdvice: loadAdvice, sleepNight: sleepNight, baselineProgress: baselineProgress, facts: facts)
    }
}
