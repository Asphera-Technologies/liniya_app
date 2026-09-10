//
//  GoalEditorView.swift
//  Linea
//
//  Create/edit a goal, including updating progress and marking complete.
//  Native sheet, Linea-styled. Talks to `PlanStore` intents only.
//
//  A goal has a horizon (week/month) because that is what makes it comparable
//  to today: the Decision Engine raises tasks linked to a goal that is running
//  out of time. Progress is derived from linked tasks when there are any —
//  the slider stays for goals that are not broken into tasks yet.
//

import SwiftUI

struct GoalEditorView: View {
    @Environment(PlanStore.self) private var plan
    @Environment(\.dismiss) private var dismiss

    let existing: LineaGoal?

    @State private var title: String
    @State private var progress: Double
    @State private var isCompleted: Bool
    @State private var horizon: GoalHorizon
    @State private var isActive: Bool
    @FocusState private var titleFocused: Bool
    @Namespace private var segments

    init(existing: LineaGoal? = nil) {
        self.existing = existing
        _title = State(initialValue: existing?.title ?? "")
        _progress = State(initialValue: existing?.progress ?? 0)
        _isCompleted = State(initialValue: existing?.isCompleted ?? false)
        _horizon = State(initialValue: existing?.horizon ?? .week)
        _isActive = State(initialValue: existing?.isActive ?? true)
    }

    private var isEditing: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LineaMetrics.sectionSpacing) {
                    LineaTextField(placeholder: "Название цели", text: $title, axis: .vertical)
                        .focused($titleFocused)

                    horizonSection
                    progressSection

                    VStack(spacing: 0) {
                        Toggle(isOn: $isActive.animation(.snappy)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Активная")
                                    .font(LineaFont.rowTitle)
                                    .foregroundStyle(LineaColor.textPrimary)
                                Text("Linea поднимает задачи активных целей")
                                    .font(LineaFont.caption)
                                    .foregroundStyle(LineaColor.textTertiary)
                            }
                        }
                        .tint(LineaColor.ink)
                        .padding(.vertical, 14)
                        LineaHairline()

                        Toggle(isOn: $isCompleted.animation(.snappy)) {
                            Text("Выполнено")
                                .font(LineaFont.rowTitle)
                                .foregroundStyle(LineaColor.textPrimary)
                        }
                        .tint(LineaColor.ink)
                        .padding(.vertical, 14)
                        LineaHairline()
                    }

                    if isEditing {
                        Button(role: .destructive) {
                            Task {
                                if let existing { await plan.deleteGoal(existing) }
                                dismiss()
                            }
                        } label: {
                            Text("Удалить цель")
                                .font(LineaFont.control)
                                .foregroundStyle(.red)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, LineaMetrics.screenPadding)
                .padding(.vertical, 20)
            }
            .background(LineaColor.background.ignoresSafeArea())
            .navigationTitle(isEditing ? "Цель" : "Новая цель")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }.tint(LineaColor.ink)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { save() }
                        .tint(LineaColor.ink)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            if !isEditing { titleFocused = true }
        }
    }

    private var horizonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Горизонт", trailing: horizonHint)
            LineaSegmentedControl(
                options: GoalHorizon.allCases.map(\.title),
                selection: Binding(
                    get: { GoalHorizon.allCases.firstIndex(of: horizon) ?? 0 },
                    set: { horizon = GoalHorizon.allCases[$0] }
                ),
                namespace: segments
            )
        }
    }

    private var horizonHint: String? {
        let start = existing?.startDate ?? Date()
        let goal = LineaGoal(title: "", createdAt: start, horizon: horizon, startDate: start)
        let target = goal.targetDate(calendar: Calendar.current)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM"
        return "до \(formatter.string(from: target))"
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Прогресс")
                    .font(LineaFont.sectionLabel)
                    .foregroundStyle(LineaColor.textSecondary)
                Spacer()
                Text("\(Int((displayProgress * 100).rounded()))%")
                    .font(LineaFont.sectionLabel)
                    .foregroundStyle(LineaColor.textTertiary)
                    .monospacedDigit()
            }
            DashProgress(progress: displayProgress)
            Slider(value: $progress, in: 0...1, step: 0.05) {
                Text("Прогресс")
            }
            .tint(LineaColor.ink)
            .disabled(isCompleted)
            .opacity(isCompleted ? 0.4 : 1)
        }
    }

    private var displayProgress: Double {
        if isCompleted { return 1 }
        if let existing, let derived = plan.derivedProgress(for: existing) { return derived }
        return progress
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let result = LineaGoal(
            id: existing?.id ?? UUID(),
            title: trimmedTitle,
            progress: isCompleted ? 1 : progress,
            isCompleted: isCompleted,
            createdAt: existing?.createdAt ?? Date(),
            horizon: horizon,
            startDate: existing?.startDate,
            isActive: isActive
        )
        Task {
            await plan.saveGoal(result)
            dismiss()
        }
    }
}
