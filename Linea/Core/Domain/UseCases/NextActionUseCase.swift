//
//  NextActionUseCase.swift
//  Linea
//
//  «Сейчас» на экране «Сегодня» — action_score в деле. «Подготовить
//  стратегию» важна, но до встречи 20 минут: сейчас Linea предложит то, что
//  успеется, а стратегию — после встречи. Встреча прошла — стратегия снова
//  «сейчас».
//
//  Чистая функция от дня, свежих задач и времени; текст — из шаблонов
//  (`ExplanationMoment.now`), экран только показывает его.
//

import Foundation

nonisolated struct NextAction: Hashable, Sendable {
    /// Задача «сейчас»; nil — сейчас ни одна не помещается.
    let taskID: UUID?
    /// Важная задача, которой сейчас не хватает окна: «её лучше после».
    let laterTaskID: UUID?
    let headline: String
    let body: String
    let facts: [Fact]
}

nonisolated struct NextActionUseCase: Sendable {
    let engine: PriorityEngine
    let renderer: any TextRenderer

    init(config: EngineConfig = .default, renderer: any TextRenderer = RuleBasedExplainer()) {
        self.engine = PriorityEngine(config: config)
        self.renderer = renderer
    }

    /// `tasks` — свежие: после утреннего снимка человек мог что-то закрыть.
    func run(record: DayRecord, tasks: [LineaTask], calibration: Calibration, time: TimeContext) -> NextAction? {
        guard var snapshot = record.snapshot, let state = record.state,
              time.isSameDay(snapshot.day, time.now) else { return nil }
        snapshot.tasks = tasks
        let context = PriorityContext(snapshot: snapshot, state: state, calibration: calibration,
                                      config: engine.config, time: time)
        let window = context.window(at: time.now)
        // Идёт встреча или рабочий день кончился — советовать нечего.
        guard !window.isBusy else { return nil }

        let ranked = engine.rankNow(context: context)
        let minimum = engine.config.minimumActionScore
        // Принятый план — договорённость: если его блок идёт сейчас и задача
        // уместна, «сейчас» — она.
        let plannedNow = plannedTaskID(in: record.plan, at: time.now, tasks: tasks)
        let best = ranked.first { $0.taskID == plannedNow && $0.action >= minimum }
            ?? ranked.first { $0.action >= minimum }

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

        let titles = Dictionary(tasks.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        var facts: [Fact] = []
        if let best, let title = titles[best.taskID] {
            facts.append(.nowAction(taskID: best.taskID, title: title))
        }
        if let later, let title = titles[later.taskID] {
            facts.append(.laterAction(taskID: later.taskID, title: title, minutesNeeded: later.minutesNeeded))
        }
        if let until = window.until {
            facts.append(.nextCommitment(title: until.title, at: until.start, minutesLeft: window.minutes))
        } else {
            facts.append(.endOfWorkday(minutesLeft: window.minutes))
        }

        let explanation = renderer.render(ExplanationRequest(
            moment: .now,
            facts: facts,
            taskTitles: [best?.taskID, later?.taskID].compactMap { $0.flatMap { titles[$0] } },
            localeIdentifier: time.locale.identifier,
            hour: time.timeOfDay(of: time.now).hour,
            userName: snapshot.profile.name,
            timeZoneIdentifier: time.timeZone.identifier
        ))
        return NextAction(
            taskID: best?.taskID, laterTaskID: later?.taskID,
            headline: explanation.headline, body: explanation.body, facts: facts
        )
    }

    /// Задача, которую сейчас нельзя начать не из-за окна: ждёт другую, у неё
    /// своё время или её день ещё не настал. О такой «после встречи» не скажешь.
    private static func isOutOfReach(_ limit: ActionLimit) -> Bool {
        switch limit {
        case .blocked, .fixedTime, .plannedLater, .busy: return true
        case .shortWindow, .lowEnergy: return false
        }
    }

    private func plannedTaskID(in plan: DayPlan?, at moment: Date, tasks: [LineaTask]) -> UUID? {
        guard let plan, plan.status == .accepted else { return nil }
        let open = Set(tasks.filter { !$0.isDone }.map(\.id))
        return plan.blocks.first { block in
            block.kind == .focus && block.start <= moment && moment < block.end
                && (block.taskID.map { open.contains($0) } ?? false)
        }?.taskID
    }
}
