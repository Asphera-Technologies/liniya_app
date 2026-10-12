//
//  GoalRevision.swift
//  Linea
//
//  Человек сохранил цель — значит, пересмотрел её: время пересмотра
//  (`last_reviewed_at`) — сейчас. Что он при этом сдвинул вперёд — закрыл
//  этап, приблизил число к цели, перешёл на следующую стадию, отметил «почти
//  готово», — попадает в журнал продвижений цели. Из журнала и закрытых
//  задач цели Linea знает последнее продвижение и сколько значимых действий
//  было за 30 дней (`GoalProgressEngine`).
//
//  Откат — не продвижение: снятый этап, упавшее число и шаг назад по
//  стадиям журнал не пишет, и записанное раньше не стирается.
//

import Foundation

nonisolated enum GoalRevision {
    /// Сколько продвижений хранит цель: на год активной работы хватает.
    static let logLimit = 200

    /// Цель, которую сохраняет человек. Журнал ведётся от сохранённой версии:
    /// экран его не правит и не может потерять.
    static func saved(previous: LineaGoal?, updated: LineaGoal, time: TimeContext) -> LineaGoal {
        var goal = updated
        goal.lastReviewedAt = time.now
        guard let previous else { return goal }

        goal.metrics = updated.metrics.map { metric in
            var metric = metric
            if let old = previous.metrics.first(where: { $0.id == metric.id }), old.current != metric.current {
                metric.updatedAt = time.now
            }
            return metric
        }
        let events = progress(from: previous, to: goal, at: time.now)
        goal.progressLog = Array((previous.progressLog + events).suffix(logLimit))
        return goal
    }

    /// Что сдвинулось вперёд между двумя версиями цели.
    static func progress(from previous: LineaGoal, to updated: LineaGoal, at moment: Date) -> [GoalProgressEvent] {
        var events: [GoalProgressEvent] = []

        for milestone in updated.milestones where milestone.isDone {
            let wasDone = previous.milestones.first { $0.id == milestone.id }?.isDone ?? false
            if !wasDone {
                events.append(GoalProgressEvent(kind: .milestoneDone, at: milestone.completedAt ?? moment, detail: milestone.title))
            }
        }

        for metric in updated.metrics {
            guard let old = previous.metrics.first(where: { $0.id == metric.id }), old.current != metric.current else { continue }
            // Ближе к цели — продвижение; дальше — нет.
            if abs(metric.target - metric.current) < abs(old.target - old.current) {
                events.append(GoalProgressEvent(kind: .metricUpdated, at: moment,
                                                detail: GoalProgressText.amount(metric.current, unit: metric.unit)))
            }
        }

        // Стадия — вперёд по списку стадий этой цели. Первая выбранная стадия —
        // не движение, а то, где цель уже была.
        if let stage = updated.stage, let old = previous.stage, stage != old,
           let newIndex = updated.stages.firstIndex(of: stage), let oldIndex = updated.stages.firstIndex(of: old),
           newIndex > oldIndex {
            events.append(GoalProgressEvent(kind: .stageChanged, at: moment, detail: stage))
        }

        if updated.manualState != nil, updated.manualState != previous.manualState {
            let order = GoalManualState.allCases
            let new = updated.reportedState
            let old = previous.reportedState
            if let newIndex = order.firstIndex(of: new), let oldIndex = order.firstIndex(of: old), newIndex > oldIndex {
                events.append(GoalProgressEvent(kind: .manualStateChanged, at: moment, detail: new.title))
            }
        }
        return events
    }
}
