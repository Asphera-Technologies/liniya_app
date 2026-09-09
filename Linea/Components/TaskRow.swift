//
//  TaskRow.swift
//  Linea
//
//  A task row: a circular checkbox (filled ink when done), the title (struck
//  through and dimmed when done), an optional meta line, an optional "Важно"
//  tag, a chevron, and a delete affordance. Bound to the `LineaTask` domain.
//

import SwiftUI

struct TaskRow: View {
    let task: LineaTask
    var onToggle: () -> Void = {}
    var onOpen: () -> Void = {}
    var onDelete: () -> Void = {}

    private var tag: String? {
        task.priority.isImportant ? "Важно" : nil
    }

    private var meta: String? {
        task.notes?.isEmpty == false ? task.notes : nil
    }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(task.isDone ? LineaColor.ink : LineaColor.textTertiary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Отметить невыполненной" : "Отметить выполненной")

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(LineaFont.rowTitle)
                        .strikethrough(task.isDone, color: LineaColor.textTertiary)
                        .foregroundStyle(task.isDone ? LineaColor.textTertiary : LineaColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let meta {
                        Text(meta)
                            .font(LineaFont.caption)
                            .foregroundStyle(LineaColor.textTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let tag {
                Text(tag)
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textSecondary)
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(LineaColor.textTertiary)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(LineaColor.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Удалить задачу")
        }
        .padding(.vertical, 14)
    }
}
