//
//  PlanView.swift
//  Linea
//
//  The Plan screen: a Week/Month scope toggle, a date navigator, real goals
//  with dash progress, and real date-grouped tasks — all persisted locally via
//  `PlanStore` (SwiftData behind repositories). Tapping a row edits it; the
//  add rows create; the checkbox toggles; the × deletes.
//

import SwiftUI

struct PlanView: View {
    @Environment(PlanStore.self) private var plan
    @Namespace private var segmentNamespace

    @State private var editingTask: TaskEditTarget?
    @State private var editingGoal: GoalEditTarget?

    var body: some View {
        @Bindable var plan = plan

        NavigationStack {
            LineaScaffold(title: "План") {
                LineaSegmentedControl(
                    options: ["Неделя", "Месяц"],
                    selection: Binding(
                        get: { plan.scope.rawValue },
                        set: { plan.scope = PlanScope(rawValue: $0) ?? .week }
                    ),
                    namespace: segmentNamespace
                )

                WeekNavigator(
                    title: plan.intervalLabel,
                    onPrevious: { plan.goToPrevious() },
                    onNext: { plan.goToNext() }
                )

                if let warning = plan.warningMessage {
                    Text(warning)
                        .font(LineaFont.caption)
                        .foregroundStyle(LineaColor.textSecondary)
                }

                goalsSection
                tasksSection
            }
        }
        .task { await plan.load() }
        .sheet(item: $editingTask) { target in
            switch target {
            case .new(let date): TaskEditorView(defaultDate: date)
            case .edit(let task): TaskEditorView(existing: task)
            }
        }
        .sheet(item: $editingGoal) { target in
            switch target {
            case .new: GoalEditorView()
            case .edit(let goal): GoalEditorView(existing: goal)
            }
        }
    }

    // MARK: Goals

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: "Цели")
            if plan.goals.isEmpty {
                emptyHint("Пока нет целей")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(plan.goals.enumerated()), id: \.element.id) { index, goal in
                        GoalRow(goal: goal) { editingGoal = .edit(goal) }
                        if index < plan.goals.count - 1 { LineaHairline() }
                    }
                }
            }
            addRow(title: "Цель") { editingGoal = .new }
        }
    }

    // MARK: Tasks

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(plan.taskSections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: section.id)
                    VStack(spacing: 0) {
                        ForEach(Array(section.tasks.enumerated()), id: \.element.id) { index, task in
                            TaskRow(
                                task: task,
                                onToggle: { Task { await plan.toggleTask(task) } },
                                onOpen: { editingTask = .edit(task) },
                                onDelete: { Task { await plan.deleteTask(task) } }
                            )
                            if index < section.tasks.count - 1 { LineaHairline() }
                        }
                    }
                }
            }

            if plan.taskSections.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Задачи")
                    emptyHint("На этот период задач нет")
                }
            }

            addRow(title: "Задача") {
                editingTask = .new(Calendar.current.startOfDay(for: Date()))
            }
        }
    }

    // MARK: Building blocks

    private func addRow(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.footnote.weight(.medium))
                Text(title)
                    .font(LineaFont.rowTitle)
            }
            .foregroundStyle(LineaColor.textTertiary)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(LineaFont.rowTitle)
            .foregroundStyle(LineaColor.textTertiary)
            .padding(.vertical, 14)
    }
}

// MARK: - Sheet routes

enum TaskEditTarget: Identifiable {
    case new(Date?)
    case edit(LineaTask)

    var id: String {
        switch self {
        case .new: return "new-task"
        case .edit(let task): return task.id.uuidString
        }
    }
}

enum GoalEditTarget: Identifiable {
    case new
    case edit(LineaGoal)

    var id: String {
        switch self {
        case .new: return "new-goal"
        case .edit(let goal): return goal.id.uuidString
        }
    }
}
