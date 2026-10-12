//
//  GoalProgressBar.swift
//  Linea
//
//  Полоска прогресса цели — только когда её честно можно нарисовать
//  (ADR-037): у числа и у этапов с весами — доля, у этапов без весов —
//  отрезки, по одному на этап. У «отмечаю сам» и «без процентов» полоски
//  нет. Одна и та же в строке цели в «Плане» и в карточке цели.
//

import SwiftUI

struct GoalProgressBar: View {
    let progress: GoalProgress

    var body: some View {
        switch progress.bar {
        case .fraction(let value)?:
            DashProgress(progress: value)
        case .steps(let done, let total)?:
            // Этапы без весов — отрезками: каждый отрезок — этап, а не проценты.
            DashProgress(progress: Double(done) / Double(max(total, 1)), segments: min(max(total, 1), 12),
                         valueDescription: GoalProgressText.milestones(done: done, total: total))
        case nil:
            EmptyView()
        }
    }
}
