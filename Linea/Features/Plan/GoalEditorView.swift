//
//  GoalEditorView.swift
//  Linea
//
//  Create/edit a goal, including updating progress and marking complete.
//  Native sheet, Linea-styled. Talks to `PlanStore` intents only.
//
//  У цели есть срок — дата, к которой она должна быть достигнута. Именно он
//  делает цель сопоставимой с сегодняшним днём: чем ближе срок, тем выше
//  Decision Engine поднимает связанные задачи. Срок необязателен: без него
//  цель просто активна и тянет ровно.
//
//  Прогресс считается из связанных задач, если они есть; слайдер остаётся для
//  целей, которые ещё не разложены на задачи.
//

import SwiftUI

struct GoalEditorView: View {
    @Environment(PlanStore.self) private var plan
    @Environment(\.dismiss) private var dismiss

    let existing: LineaGoal?

    @State private var title: String
    @State private var progress: Double
    @State private var isCompleted: Bool
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var isActive: Bool
    /// Chosen once per editor: a second «Готово» updates the same goal
    /// instead of creating a duplicate.
    @State private var newGoalID = UUID()
    /// «Готово» and «Удалить» fire once; a double tap used to create two goals.
    @State private var isSaving = false
    @FocusState private var titleFocused: Bool

    init(existing: LineaGoal? = nil) {
        self.existing = existing
        _title = State(initialValue: existing?.title ?? "")
        _progress = State(initialValue: existing?.progress ?? 0)
        _isCompleted = State(initialValue: existing?.isCompleted ?? false)
        _hasDueDate = State(initialValue: existing?.endDate != nil)
        _dueDate = State(initialValue: existing?.endDate ?? Self.defaultDueDate())
        _isActive = State(initialValue: existing?.isActive ?? true)
    }

    private var isEditing: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LineaMetrics.sectionSpacing) {
                    LineaTextField(placeholder: "Название цели", text: $title, axis: .vertical)
                        .focused($titleFocused)

                    dueDateSection
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
                            guard !isSaving else { return }
                            isSaving = true
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
                        .disabled(trimmedTitle.isEmpty || isSaving)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            if !isEditing { titleFocused = true }
        }
    }

    private var dueDateSection: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $hasDueDate.animation(.snappy)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Срок")
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textPrimary)
                    Text(hasDueDate ? dueDateHint : "Без срока цель просто активна")
                        .font(LineaFont.caption)
                        .foregroundStyle(LineaColor.textTertiary)
                }
            }
            .tint(LineaColor.ink)
            .padding(.vertical, 14)
            LineaHairline()

            if hasDueDate {
                DatePicker("", selection: $dueDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(LineaColor.ink)
                    .labelsHidden()
                    .padding(.top, 4)
            }
        }
    }

    /// Сколько осталось — это и есть то, что двигает задачи цели вверх.
    private var dueDateHint: String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()),
                                           to: calendar.startOfDay(for: dueDate)).day ?? 0
        if days < 0 { return "Срок прошёл" }
        if days == 0 { return "Сегодня последний день" }
        return "Осталось \(days) \(Self.dayWord(days))"
    }

    private static func dayWord(_ n: Int) -> String {
        let lastTwo = abs(n) % 100
        if (11...14).contains(lastTwo) { return "дней" }
        switch abs(n) % 10 {
        case 1: return "день"
        case 2, 3, 4: return "дня"
        default: return "дней"
        }
    }

    /// По умолчанию — конец текущей недели: самый частый горизонт цели.
    private static func defaultDueDate() -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: 7, to: today) ?? today
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
        guard !isSaving else { return }
        isSaving = true
        let result = LineaGoal(
            id: existing?.id ?? newGoalID,
            title: trimmedTitle,
            progress: isCompleted ? 1 : progress,
            isCompleted: isCompleted,
            createdAt: existing?.createdAt ?? Date(),
            startDate: existing?.startDate,
            endDate: hasDueDate ? Calendar.current.startOfDay(for: dueDate) : nil,
            isActive: isActive
        )
        Task {
            await plan.saveGoal(result)
            dismiss()
        }
    }
}
