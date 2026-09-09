//
//  GoalRow.swift
//  Linea
//
//  A goal row: title with a chevron, a dash progress bar, and a quiet status
//  line beneath (e.g. "Выполнено", "50%"). Bound to the `LineaGoal` domain.
//

import SwiftUI

struct GoalRow: View {
    let goal: LineaGoal
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text(goal.title)
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textPrimary)
                        .strikethrough(goal.isCompleted, color: LineaColor.textTertiary)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(LineaColor.textTertiary)
                }
                DashProgress(progress: goal.isCompleted ? 1 : goal.progress)
                Text(goal.statusText)
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textTertiary)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
