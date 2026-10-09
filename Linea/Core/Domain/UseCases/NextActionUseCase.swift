//
//  NextActionUseCase.swift
//  Linea
//
//  «Сейчас» на экране «Сегодня» — одно рекомендованное действие (`NextAction`)
//  и по просьбе ещё два-три. «Подготовить стратегию» важна, но до встречи
//  20 минут: сейчас Linea предложит то, что успеется, а стратегию — после
//  встречи. Встреча прошла — стратегия снова «сейчас».
//
//  Действие и задача — разные сущности: у действия — момент, окно и
//  отведённое время. «Начать» (`TaskExecutionUseCase`) пишет в день отклик
//  `actionStarted`, а задаче ставит `startedAt` — так собираются данные о
//  том, как человек работает на самом деле. Пока действие идёт, «Сейчас»
//  показывает его, а план держит его время занятым (`PlanDayUseCase`).
//
//  У каждой рекомендации — причина (`NowReasoner`): одна короткая фраза,
//  понятная без техники.
//
//  Чистая функция от дня, свежих задач и времени; текст — из шаблонов
//  (`ExplanationMoment.now`), экран только показывает его.
//

import Foundation

nonisolated struct NextActionUseCase: Sendable {
    /// Окно длиннее — о нём не говорим: «до конца дня 12 ч» утром — шум.
    static let windowWorthMentioningMinutes = 120
    /// «Другое» — не больше трёх: длинный список задач — не совет.
    static let maxAlternatives = 3

    let engine: PriorityEngine
    let renderer: any TextRenderer
    let reasoner = NowReasoner()

    init(config: EngineConfig = .default, renderer: any TextRenderer = RuleBasedExplainer()) {
        self.engine = PriorityEngine(config: config)
        self.renderer = renderer
    }

    /// Обязательство, которым начатое действие занимает время в плане.
    static func commitmentID(for taskID: UUID) -> String {
        "action-\(taskID.uuidString)"
    }

    /// `tasks` — свежие: после утреннего снимка человек мог что-то закрыть.
    /// `preferred` — задача, которую человек выбрал в «Другое».
    func run(
        record: DayRecord,
        tasks: [LineaTask],
        calibration: Calibration,
        time: TimeContext,
        preferred: UUID? = nil
    ) -> NextAction? {
        guard var snapshot = record.snapshot, let state = record.state,
              time.isSameDay(snapshot.day, time.now) else { return nil }
        snapshot.tasks = tasks
        let active = record.activeAction(tasks: tasks, at: time.now)
        // План держит время начатого действия занятым. Для «Другое» считаем
        // без него: что ещё можно сделать вместо.
        if let active {
            snapshot.commitments.removeAll { $0.id == Self.commitmentID(for: active.start.taskID) }
        }
        let context = PriorityContext(snapshot: snapshot, state: state, calibration: calibration,
                                      config: engine.config, time: time)
        let window = context.window(at: time.now)
        let titles = Dictionary(tasks.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        let minimum = engine.config.minimumActionScore
        let ranked = window.isBusy ? [] : engine.rankNow(context: context)
        let actionable = ranked.filter { $0.action >= minimum }

        // Человек уже взялся за действие — оно и есть «сейчас».
        if let active, let title = titles[active.start.taskID] {
            let option = NextAction.Option(taskID: active.start.taskID, title: title, minutes: active.start.minutes)
            let alternatives = actionable.filter { $0.taskID != option.taskID }
                .prefix(Self.maxAlternatives)
                .compactMap { Self.option($0, titles: titles) }
            let facts: [Fact] = [
                .nowAction(taskID: option.taskID, title: title),
                .actionStarted(at: active.at, minutes: active.start.minutes),
            ]
            let explanation = render(facts, snapshot: snapshot, time: time)
            return NextAction(
                option: option, alternatives: Array(alternatives), laterTaskID: nil, startedAt: active.at,
                headline: explanation.headline, reason: explanation.body, facts: facts
            )
        }

        // Идёт встреча или рабочий день кончился — советовать нечего.
        guard !window.isBusy else { return nil }

        // Принятый план — договорённость: если его блок идёт сейчас и задача
        // уместна, «сейчас» — она. Выбор человека в «Другое» сильнее плана.
        let plannedNow = plannedTaskID(in: record.plan, at: time.now, tasks: tasks)
        let best = actionable.first { $0.taskID == preferred }
            ?? actionable.first { $0.taskID == plannedNow }
            ?? actionable.first
        let alternatives = actionable.filter { $0.taskID != best?.taskID }
            .prefix(Self.maxAlternatives)
            .compactMap { Self.option($0, titles: titles) }

        // Самая важная задача, которую можно было бы начать, будь окно длиннее.
        let waiting = ranked.enumerated()
            .filter { _, candidate in
                candidate.limits.contains { $0.isShortWindow } && !candidate.limits.contains(where: Self.isOutOfReach)
            }
            .sorted { lhs, rhs in
                lhs.element.importance != rhs.element.importance
                    ? lhs.element.importance > rhs.element.importance
                    : lhs.offset < rhs.offset
            }
            .first?.element
        let later = waiting.flatMap { candidate in
            candidate.taskID != best?.taskID && candidate.importance > (best?.importance ?? 0) ? candidate : nil
        }
        guard best != nil || later != nil else { return nil }

        var facts: [Fact] = []
        if let best, let title = titles[best.taskID] {
            facts.append(.nowAction(taskID: best.taskID, title: title))
        }
        if let later, let title = titles[later.taskID] {
            facts.append(.laterAction(taskID: later.taskID, title: title, minutesNeeded: later.minutesNeeded))
        }
        // Окно упоминается, когда оно и есть причина: важное или ничего не
        // помещается, либо до следующего дела не больше двух часов.
        if later != nil || best == nil || window.minutes <= Self.windowWorthMentioningMinutes {
            facts.append(.windowUntil(kind: window.until?.kind, title: window.until?.title, minutesLeft: window.minutes))
        }
        // У каждой рекомендации — одна причина, понятная без техники.
        if let best, let task = tasks.first(where: { $0.id == best.taskID }) {
            let choice = NowReasoner.Choice(
                task: task, assessment: best, window: window,
                laterTitle: later.flatMap { titles[$0.taskID] },
                isPlanned: best.taskID == plannedNow
            )
            facts.append(.nowReason(reasoner.reason(for: choice, context: context)))
        }

        let explanation = render(facts, snapshot: snapshot, time: time)
        return NextAction(
            option: best.flatMap { Self.option($0, titles: titles) },
            alternatives: Array(alternatives),
            laterTaskID: later?.taskID,
            startedAt: nil,
            headline: explanation.headline,
            reason: explanation.body,
            facts: facts
        )
    }

    private func render(_ facts: [Fact], snapshot: ContextSnapshot, time: TimeContext) -> Explanation {
        renderer.render(ExplanationRequest(
            moment: .now,
            facts: facts,
            localeIdentifier: time.locale.identifier,
            hour: time.timeOfDay(of: time.now).hour,
            userName: snapshot.profile.name,
            timeZoneIdentifier: time.timeZone.identifier
        ))
    }

    private static func option(_ assessment: PriorityAssessment, titles: [UUID: String]) -> NextAction.Option? {
        titles[assessment.taskID].map {
            NextAction.Option(taskID: assessment.taskID, title: $0, minutes: assessment.minutesNeeded)
        }
    }

    /// Задача, которую сейчас нельзя начать не из-за окна: ждёт другую, у неё
    /// своё время или её день ещё не настал. О такой «после встречи» не скажешь.
    private static func isOutOfReach(_ limit: ActionLimit) -> Bool {
        switch limit {
        case .blocked, .fixedTime, .plannedLater, .busy, .notNow: return true
        case .shortWindow, .lowEnergy: return false
        }
    }

    private func plannedTaskID(in plan: DayPlan?, at moment: Date, tasks: [LineaTask]) -> UUID? {
        guard let plan, plan.status == .accepted else { return nil }
        let open = Set(tasks.filter(\.isOpen).map(\.id))
        return plan.blocks.first { block in
            block.kind == .focus && block.start <= moment && moment < block.end
                && (block.taskID.map { open.contains($0) } ?? false)
        }?.taskID
    }
}
