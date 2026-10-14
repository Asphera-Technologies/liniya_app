//
//  DurationEstimate.swift
//  Linea
//
//  Сколько займёт задача, если человек не сказал (ADR-045): Linea оценивает
//  сама — «Ответить клиенту ~10 мин», «Подготовить презентацию ~1 ч» — и
//  помнит, откуда оценка (`estimated_duration_source`):
//    • user    — сказал или выбрал человек;
//    • ai      — оценила Linea по словам названия и типу задачи;
//    • learned — по тому, сколько похожие задачи заняли у этого человека на
//                самом деле (`actual_duration`).
//

import Foundation

nonisolated enum DurationSource: String, Codable, CaseIterable, Hashable, Sendable {
    case user
    case ai
    case learned
}

/// Оценка Linea: сколько минут и почему.
nonisolated struct DurationEstimate: Hashable, Sendable {
    let minutes: Int
    /// `ai` или `learned`; `user` оценкой Linea не бывает.
    let source: DurationSource
    /// По скольким похожим задачам — у `learned`; у `ai` — 0.
    let samples: Int
}

/// Как оценку видит человек — в карточке задачи под «Сколько займёт».
nonisolated enum DurationText {
    /// «~10 мин — оценка Linea», «~25 мин — по твоим похожим задачам»; у
    /// длительности, которую задал человек, — nil.
    static func estimate(of task: LineaTask) -> String? {
        guard let minutes = task.estimatedMinutes, task.isDurationEstimatedByLinea else { return nil }
        let duration = QuickTaskText.duration(minutes: minutes)
        return task.estimatedDurationSource == .learned
            ? "\(duration) — по твоим похожим задачам"
            : "\(duration) — оценка Linea"
    }
}
