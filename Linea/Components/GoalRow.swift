//
//  GoalRow.swift
//  Linea
//
//  A goal row: title with a chevron, a dash bar and a quiet line beneath —
//  progress the way it can honestly be shown (ADR-037): «18 из 50
//  пользователей · 36%», «2 из 5 этапов», «В процессе», «Разработка ·
//  последнее продвижение — вчера», and the deadline. The bar is there only
//  for a number or for milestones; a goal without percentages gets none.
//

import SwiftUI

struct GoalRow: View {
    let goal: LineaGoal
    let progress: GoalProgress
    let time: TimeContext
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text(goal.title)
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textPrimary)
                        .strikethrough(goal.isCompleted, color: LineaColor.textTertiary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(LineaColor.textTertiary)
                }
                bar
                Text(caption)
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textTertiary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var bar: some View {
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

    /// Прогресс и срок: «18 из 50 пользователей · 36% · до 15 окт».
    private var caption: String {
        var text = GoalProgressText.summary(progress, time: time)
        if !goal.isCompleted, let end = goal.endDate {
            text += GoalProgressText.separator + GoalProgressText.shortDeadline(end, time: time)
        }
        return text
    }
}
