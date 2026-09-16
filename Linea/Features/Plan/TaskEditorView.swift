//
//  TaskEditorView.swift
//  Linea
//
//  Create/edit a task. Presented as a native sheet but styled with the Linea
//  design system (calm fields, hairlines, ink accents) rather than a generic
//  Form. Talks to `PlanStore` intents only.
//
//  Three different times, on purpose (see Core/Domain/Models/PlanModels.swift):
//    • «Дата»          — the day the task is planned for;
//    • «Дедлайн»       — when it must be done by (this is what drives urgency);
//    • «Время начала»  — a slot the user fixed themselves; such a task becomes
//                        a commitment and the planner never moves it.
//  Duration and «Сложность» are what let Linea match work to the energy the
//  user actually has today.
//

import SwiftUI

struct TaskEditorView: View {
    @Environment(PlanStore.self) private var plan
    @Environment(\.dismiss) private var dismiss

    /// The task being edited, or nil when creating.
    let existing: LineaTask?
    /// Default date applied to a newly created task (e.g. today).
    var defaultDate: Date?

    @State private var title: String
    @State private var priority: TaskPriority
    @State private var demand: CognitiveDemand
    @State private var estimatedMinutes: Int?
    @State private var hasDate: Bool
    @State private var date: Date
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var hasStart: Bool
    @State private var start: Date
    @State private var goalID: UUID?
    @FocusState private var titleFocused: Bool
    @Namespace private var prioritySegments
    @Namespace private var demandSegments

    private static let durations = [15, 30, 45, 60, 90, 120]
    private let matcher = KeywordGoalMatcher()

    init(existing: LineaTask? = nil, defaultDate: Date? = nil) {
        self.existing = existing
        self.defaultDate = defaultDate
        _title = State(initialValue: existing?.title ?? "")
        _priority = State(initialValue: existing?.priority ?? .normal)
        _demand = State(initialValue: existing?.cognitiveDemand ?? .normal)
        _estimatedMinutes = State(initialValue: existing?.estimatedMinutes)
        let initialDate = existing?.date ?? defaultDate
        _hasDate = State(initialValue: initialDate != nil)
        _date = State(initialValue: initialDate ?? Date())
        _hasDeadline = State(initialValue: existing?.deadline != nil)
        _deadline = State(initialValue: existing?.deadline ?? Self.defaultDeadline(for: initialDate))
        _hasStart = State(initialValue: existing?.scheduledStart != nil)
        _start = State(initialValue: existing?.scheduledStart ?? Self.defaultStart(for: initialDate))
        _goalID = State(initialValue: existing?.goalID)
    }

    private var isEditing: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LineaMetrics.sectionSpacing) {
                    LineaTextField(placeholder: "Что нужно сделать?", text: $title, axis: .vertical)
                        .focused($titleFocused)

                    goalSection
                    prioritySection
                    demandSection
                    durationSection
                    scheduleSection

                    if isEditing { deleteButton }
                }
                .padding(.horizontal, LineaMetrics.screenPadding)
                .padding(.vertical, 20)
            }
            .background(LineaColor.background.ignoresSafeArea())
            .navigationTitle(isEditing ? "Задача" : "Новая задача")
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

    // MARK: Goal

    @ViewBuilder
    private var goalSection: some View {
        let goals = plan.activeGoals
        if !goals.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Цель")
                VStack(spacing: 0) {
                    goalRow(title: "Без цели", isSelected: goalID == nil) { goalID = nil }
                    ForEach(goals) { goal in
                        LineaHairline()
                        goalRow(title: goal.title, isSelected: goalID == goal.id) { goalID = goal.id }
                    }
                }
                if let suggestion, goalID == nil {
                    Button {
                        withAnimation(.snappy) { goalID = suggestion.id }
                    } label: {
                        Text("Похоже, это к цели «\(suggestion.title)» — связать?")
                            .font(LineaFont.caption)
                            .foregroundStyle(LineaColor.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// A lexical hint only — Linea never links a task to a goal by itself.
    private var suggestion: LineaGoal? {
        guard goalID == nil, trimmedTitle.count >= 4 else { return nil }
        guard let match = matcher.bestMatch(for: trimmedTitle, in: plan.activeGoals) else { return nil }
        return plan.activeGoals.first { $0.id == match.goalID }
    }

    private func goalRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(LineaFont.rowTitle)
                    .foregroundStyle(LineaColor.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(LineaColor.ink)
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: Priority & demand

    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Приоритет")
            LineaSegmentedControl(
                options: TaskPriority.allCases.map(\.title),
                selection: Binding(
                    get: { TaskPriority.allCases.firstIndex(of: priority) ?? 1 },
                    set: { priority = TaskPriority.allCases[$0] }
                ),
                namespace: prioritySegments
            )
        }
    }

    private var demandSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Сложность", trailing: demandHint)
            LineaSegmentedControl(
                options: CognitiveDemand.allCases.map(\.title),
                selection: Binding(
                    get: { CognitiveDemand.allCases.firstIndex(of: demand) ?? 1 },
                    set: { demand = CognitiveDemand.allCases[$0] }
                ),
                namespace: demandSegments
            )
        }
    }

    private var demandHint: String {
        switch demand {
        case .light: return "рутина"
        case .normal: return "обычная работа"
        case .deep: return "требует головы"
        }
    }

    // MARK: Duration

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Сколько займёт")
            HStack(spacing: 8) {
                ForEach(Self.durations, id: \.self) { minutes in
                    durationChip(minutes)
                }
            }
        }
    }

    private func durationChip(_ minutes: Int) -> some View {
        let isSelected = estimatedMinutes == minutes
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                estimatedMinutes = isSelected ? nil : minutes
            }
        } label: {
            Text(minutes < 60 ? "\(minutes)м" : "\(minutes / 60)ч\(minutes % 60 == 0 ? "" : "\(minutes % 60)")")
                .font(LineaFont.control)
                .foregroundStyle(isSelected ? LineaColor.onInk : LineaColor.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: LineaMetrics.controlRadius - 2, style: .continuous)
                        .fill(isSelected ? LineaColor.ink : LineaColor.fill)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(minutes) минут")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: Dates

    private var scheduleSection: some View {
        VStack(spacing: 0) {
            toggleRow(title: "Дата", isOn: $hasDate.animation(.snappy))
            if hasDate {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(LineaColor.ink)
                    .labelsHidden()
                    .padding(.top, 4)
            }
            toggleRow(title: "Дедлайн", isOn: $hasDeadline.animation(.snappy))
            if hasDeadline {
                DatePicker("", selection: $deadline, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .tint(LineaColor.ink)
                    .padding(.vertical, 8)
            }
            toggleRow(title: "Время начала", isOn: $hasStart.animation(.snappy))
            if hasStart {
                VStack(alignment: .leading, spacing: 6) {
                    DatePicker("", selection: $start, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(LineaColor.ink)
                    Text("Linea не будет переносить эту задачу и учтёт её как занятое время.")
                        .font(LineaFont.caption)
                        .foregroundStyle(LineaColor.textTertiary)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            Task {
                if let existing { await plan.deleteTask(existing) }
                dismiss()
            }
        } label: {
            Text("Удалить задачу")
                .font(LineaFont.control)
                .foregroundStyle(.red)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            Toggle(isOn: isOn) {
                Text(title)
                    .font(LineaFont.rowTitle)
                    .foregroundStyle(LineaColor.textPrimary)
            }
            .tint(LineaColor.ink)
            .padding(.vertical, 14)
            LineaHairline()
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Defaults & saving

    private static func defaultDeadline(for day: Date?) -> Date {
        let base = day ?? Date()
        let calendar = Calendar.current
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: base) ?? base
    }

    private static func defaultStart(for day: Date?) -> Date {
        let base = day ?? Date()
        let calendar = Calendar.current
        return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: base) ?? base
    }

    /// Fixed start and deadline always live on the planned day, so moving the
    /// day moves them too and the planner never sees a slot from another date.
    private func moment(_ time: Date, onto day: Date?) -> Date {
        guard let day else { return time }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: day) ?? time
    }

    private func save() {
        let day = hasDate ? Calendar.current.startOfDay(for: date) : nil
        let result = LineaTask(
            id: existing?.id ?? UUID(),
            title: trimmedTitle,
            notes: existing?.notes,
            date: day,
            priority: priority,
            isDone: existing?.isDone ?? false,
            createdAt: existing?.createdAt ?? Date(),
            deadline: hasDeadline ? moment(deadline, onto: day ?? deadline) : nil,
            scheduledStart: hasStart ? moment(start, onto: day) : nil,
            estimatedMinutes: estimatedMinutes,
            cognitiveDemand: demand,
            goalID: goalID,
            completedAt: existing?.completedAt
        )
        Task {
            await plan.saveTask(result)
            dismiss()
        }
    }
}
