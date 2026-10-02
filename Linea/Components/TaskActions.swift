//
//  TaskActions.swift
//  Linea
//
//  Что можно сделать с задачей прямо в списке, не открывая карточку:
//  свайп вправо — «Готово» (у закрытой — «Вернуть»), свайп влево —
//  «Перенести», долгое нажатие — «Изменить», «Привязать к цели», «Изменить
//  приоритет», «Удалить». Одинаково в «Плане» и в «Дальше» на «Сегодня».
//  Строка только зовёт обработчики, решают сторы.
//

import SwiftUI

/// Обработчики действий со строкой задачи.
struct TaskRowActions {
    /// Цели, к которым можно привязать задачу: активные и та, что уже стоит.
    var goals: [LineaGoal]
    var onDone: () -> Void
    var onReschedule: () -> Void
    var onEdit: () -> Void
    var onLinkGoal: (UUID?) -> Void
    var onPriority: (TaskPriority) -> Void
    var onDelete: () -> Void
}

extension View {
    /// Свайпы и меню долгого нажатия для строки задачи; `nil` — строка как есть.
    @ViewBuilder
    func taskActions(_ actions: TaskRowActions?, for task: LineaTask) -> some View {
        if let actions {
            SwipeActionsRow(
                leading: SwipeAction(
                    title: task.isDone ? "Вернуть" : "Готово",
                    systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark",
                    perform: actions.onDone
                ),
                // Закрытую задачу переносить некуда.
                trailing: task.isDone ? nil : SwipeAction(
                    title: "Перенести", systemImage: "calendar", tone: .quiet, perform: actions.onReschedule
                )
            ) {
                self
            }
            .contextMenu {
                TaskActionsMenu(task: task, actions: actions)
            }
        } else {
            self
        }
    }

    /// Те же «Готово» и «Перенести» для VoiceOver: свайп ему недоступен.
    @ViewBuilder
    func taskAccessibilityActions(_ actions: TaskRowActions?, for task: LineaTask) -> some View {
        if let actions {
            accessibilityActions {
                Button(task.isDone ? "Вернуть" : "Готово", action: actions.onDone)
                if !task.isDone {
                    Button("Перенести", action: actions.onReschedule)
                }
            }
        } else {
            self
        }
    }
}

/// Меню долгого нажатия на задачу.
struct TaskActionsMenu: View {
    let task: LineaTask
    let actions: TaskRowActions

    var body: some View {
        Button(action: actions.onEdit) {
            Label("Изменить", systemImage: "pencil")
        }
        goalPicker
        Picker(selection: Binding(get: { task.priority }, set: actions.onPriority)) {
            ForEach(TaskPriority.allCases, id: \.self) { priority in
                Text(priority.title).tag(priority)
            }
        } label: {
            Label("Изменить приоритет", systemImage: "flag")
        }
        .pickerStyle(.menu)
        Divider()
        Button(role: .destructive, action: actions.onDelete) {
            Label("Удалить", systemImage: "trash")
        }
    }

    /// Цели с галочкой у текущей и «Без цели». Целей нет — пункт виден, но
    /// неактивен: понятно, что привязать можно, когда цель появится.
    @ViewBuilder
    private var goalPicker: some View {
        if actions.goals.isEmpty {
            Button {} label: {
                Label("Привязать к цели", systemImage: "scope")
            }
            .disabled(true)
        } else {
            Picker(selection: Binding(get: { task.goalID }, set: actions.onLinkGoal)) {
                Text("Без цели").tag(UUID?.none)
                ForEach(actions.goals) { goal in
                    Text(goal.title).tag(Optional(goal.id))
                }
            } label: {
                Label("Привязать к цели", systemImage: "scope")
            }
            .pickerStyle(.menu)
        }
    }
}
