//
//  GoalEditorView.swift
//  Linea
//
//  Карточка цели: что человек хочет и где он сейчас относительно этого
//  (ADR-036), и прогресс — так, как его можно честно показать (ADR-037).
//
//    • Прогресс — по методу цели (`GoalProgressEditor`): число («18 из 50
//      пользователей · 36%»), этапы (✓ закрыт · ● следующий · ○ впереди;
//      процент — только когда у каждого этапа есть вес), этапы и числа,
//      «отмечаю сам» или без процентов. Метод Linea выбрала при создании,
//      здесь его можно сменить.
//    • Где сейчас — стадия (свой набор у каждой цели) и «Сейчас» словами.
//    • Результат и как поймём, что получилось.
//    • Срок, важность, сфера, чья цель, активность, тип цели.
//
//  Карточка правит свежую копию цели: всё, чего она не показывает, остаётся
//  как было. «Готово» сохраняет — это и есть пересмотр цели: время
//  пересмотра и продвижения пишет `PlanStore` (`GoalRevision`). Закрытые
//  задачи цели процент не двигают — двигают закрытые этапы и числа.
//
//  Новую цель создаёт `GoalIntakeView` (одной строкой); здесь — правка.
//

import SwiftUI

struct GoalEditorView: View {
    @Environment(PlanStore.self) private var plan
    @Environment(\.dismiss) private var dismiss

    let existing: LineaGoal

    /// Цель, которую правит карточка: новые поля модели ничто не теряет.
    @State private var draft: LineaGoal
    @State private var currentState: String
    @State private var targetState: String
    @State private var criteria: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    /// Веса этапов видны, если они уже есть или человек их включил.
    @State private var showsWeights: Bool
    @State private var isEditingStages = false
    @Namespace private var prioritySegments
    /// «Готово» and «Удалить» fire once.
    @State private var isSaving = false

    private let classifier = GoalClassifier()

    init(existing: LineaGoal) {
        self.existing = existing
        _draft = State(initialValue: existing)
        _currentState = State(initialValue: existing.currentState ?? "")
        _targetState = State(initialValue: existing.targetState ?? "")
        _criteria = State(initialValue: existing.successCriteria.joined(separator: "\n"))
        _hasDueDate = State(initialValue: existing.endDate != nil)
        _dueDate = State(initialValue: existing.endDate ?? Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date())
        _showsWeights = State(initialValue: existing.milestones.contains { $0.weight != nil })
    }

    private var time: TimeContext { plan.time }

    /// Цель так, как она сохранится, — по ней считается прогресс на экране.
    private var edited: LineaGoal {
        var goal = draft
        goal.currentState = Self.text(currentState)
        goal.endDate = hasDueDate ? time.startOfDay(dueDate) : nil
        return goal
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LineaMetrics.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 8) {
                        LineaTextField(placeholder: "Название цели", text: $draft.title, axis: .vertical)
                        if let caption = headerCaption {
                            Text(caption)
                                .font(LineaFont.caption)
                                .foregroundStyle(LineaColor.textTertiary)
                                .accessibilityIdentifier("goal.card.caption")
                        }
                    }
                    GoalProgressEditor(goal: $draft, progress: plan.progress(for: edited), time: time,
                                       showsWeights: $showsWeights)
                    stateSection
                    resultSection
                    dueDateSection
                    prioritySection
                    belongingSection
                    togglesSection
                    kindSection
                    deleteButton
                }
                .padding(.horizontal, LineaMetrics.screenPadding)
                .padding(.vertical, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(LineaColor.background.ignoresSafeArea())
            .navigationTitle("Цель")
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
    }

    /// «до 15 октября · осталось 3 дня · обновлена вчера».
    private var headerCaption: String? {
        var parts: [String] = []
        if hasDueDate { parts.append("\(GoalProgressText.deadline(time.startOfDay(dueDate), time: time)) · \(dueDateHint)") }
        if let reviewed = existing.lastReviewedAt {
            parts.append("обновлена \(GoalProgressText.moment(reviewed, time: time))")
        }
        return parts.isEmpty ? nil : RussianWords.capitalizedFirst(parts.joined(separator: GoalProgressText.separator))
    }

    // MARK: Где сейчас

    /// Стадии, которые Linea предложит цели без своих: у целей, созданных
    /// раньше, их нет.
    private var suggestedStages: [String] {
        GoalStages.suggested(kind: classifier.kind(of: edited), title: draft.title, details: GoalClassifier.story(of: edited))
    }

    private var stateSection: some View {
        let stages = draft.stages.isEmpty ? suggestedStages : draft.stages
        return VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Где сейчас")
            VStack(spacing: 0) {
                Menu {
                    ForEach(stages, id: \.self) { stage in
                        Button {
                            if draft.stages.isEmpty { draft.stages = stages }
                            draft.stage = stage
                        } label: {
                            option(stage, isSelected: draft.stage == stage)
                        }
                    }
                    Divider()
                    Button { draft.stage = nil } label: { option("Без стадии", isSelected: draft.stage == nil) }
                    Button {
                        if draft.stages.isEmpty { draft.stages = stages }
                        withAnimation(.snappy) { isEditingStages.toggle() }
                    } label: {
                        Label("Изменить стадии…", systemImage: "pencil")
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text("Стадия")
                            .font(LineaFont.rowTitle)
                            .foregroundStyle(LineaColor.textPrimary)
                        Spacer(minLength: 8)
                        Text(draft.stage ?? "Не выбрана")
                            .font(LineaFont.rowValue)
                            .foregroundStyle(draft.stage == nil ? LineaColor.textTertiary : LineaColor.textSecondary)
                            .multilineTextAlignment(.trailing)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(LineaColor.textTertiary)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Стадия: \(draft.stage ?? "не выбрана")")
                .accessibilityIdentifier("goal.stage")
                LineaHairline()
            }
            if isEditingStages {
                VStack(alignment: .leading, spacing: 6) {
                    LineaTextField(placeholder: "По одной стадии на строку", text: stagesText, axis: .vertical,
                                   font: LineaFont.rowTitle)
                        .lineLimit(2...10)
                    Text("Свой набор у каждой цели: Linea предложила его по теме цели, поправь под себя.")
                        .font(LineaFont.caption)
                        .foregroundStyle(LineaColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Что уже сделано")
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textSecondary)
                LineaTextField(placeholder: "Например: прототип готов, идёт переработка задач", text: $currentState,
                               axis: .vertical, font: LineaFont.rowTitle, identifier: "goal.current")
                    .lineLimit(1...8)
            }
        }
    }

    private var stagesText: Binding<String> {
        Binding(
            get: { draft.stages.joined(separator: "\n") },
            set: { text in
                var seen = Set<String>()
                draft.stages = text.split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && seen.insert($0).inserted }
            }
        )
    }

    // MARK: Результат

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            understandingField("Результат", placeholder: "Что будет, когда цель достигнута", text: $targetState)
            understandingField("Как поймём, что получилось", placeholder: "По одному признаку на строку", text: $criteria)
        }
    }

    private func understandingField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: label)
            LineaTextField(placeholder: placeholder, text: text, axis: .vertical, font: LineaFont.rowTitle)
                .lineLimit(1...8)
        }
    }

    // MARK: Срок и важность

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
        let days = time.days(from: time.now, to: dueDate)
        if days < 0 { return "срок прошёл" }
        if days == 0 { return "сегодня последний день" }
        return "осталось \(days) \(RussianText.plural(days, "день", "дня", "дней"))"
    }

    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Важность", trailing: draft.priority == .important ? "задачи цели выше" : nil)
            LineaSegmentedControl(
                options: TaskPriority.allCases.map(LineaGoal.importanceTitle),
                selection: Binding(
                    get: { TaskPriority.allCases.firstIndex(of: draft.priority) ?? 1 },
                    set: { draft.priority = TaskPriority.allCases[$0] }
                ),
                namespace: prioritySegments
            )
        }
    }

    // MARK: Сфера и чья цель

    private var belongingSection: some View {
        let automaticScope = classifier.scope(title: draft.title, details: GoalClassifier.story(of: edited))
        let scope = draft.scopeOverride ?? automaticScope
        return VStack(spacing: 0) {
            Menu {
                Button { draft.scopeOverride = nil } label: {
                    option("Как решит Linea: \(automaticScope.title.lowercased())", isSelected: draft.scopeOverride == nil)
                }
                Divider()
                ForEach(GoalScope.allCases, id: \.self) { option in
                    Button { draft.scopeOverride = option } label: {
                        self.option(option.title, isSelected: draft.scopeOverride == option)
                    }
                }
            } label: {
                menuRow("Сфера", value: scope.title, isMuted: draft.scopeOverride == nil)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Сфера: \(scope.title)")
            .accessibilityIdentifier("goal.scope")
            LineaHairline()

            Menu {
                ForEach(GoalOwnerScope.allCases, id: \.self) { owner in
                    Button { draft.ownerScope = owner } label: {
                        option(owner.title, isSelected: draft.ownerScope == owner)
                    }
                }
            } label: {
                menuRow("Чья цель", value: draft.ownerScope.title, isMuted: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Чья цель: \(draft.ownerScope.title)")
            .accessibilityIdentifier("goal.owner")
            LineaHairline()
        }
    }

    private func menuRow(_ title: String, value: String, isMuted: Bool) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(LineaFont.rowTitle)
                .foregroundStyle(LineaColor.textPrimary)
            Spacer(minLength: 8)
            Text(value)
                .font(LineaFont.rowValue)
                .foregroundStyle(isMuted ? LineaColor.textTertiary : LineaColor.textSecondary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(LineaColor.textTertiary)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    // MARK: Активная, выполнена

    private var togglesSection: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $draft.isActive.animation(.snappy)) {
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

            Toggle(isOn: $draft.isCompleted.animation(.snappy)) {
                Text("Выполнено")
                    .font(LineaFont.rowTitle)
                    .foregroundStyle(LineaColor.textPrimary)
            }
            .tint(LineaColor.ink)
            .padding(.vertical, 14)
            LineaHairline()
        }
    }

    // MARK: Тип цели

    /// Тип цели (`goal_type`) Linea определяет сама; от него — как она
    /// предложила считать прогресс и какие стадии. Здесь его можно поправить.
    private var kindSection: some View {
        let automatic = classifier.classify(title: draft.title, details: GoalClassifier.story(of: edited)).kind
        let current = draft.kindOverride ?? automatic
        return VStack(alignment: .leading, spacing: 6) {
            Menu {
                Button { draft.kindOverride = nil } label: {
                    option("Как решит Linea: \(automatic.title.lowercased())", isSelected: draft.kindOverride == nil)
                }
                Divider()
                ForEach(GoalKind.allCases, id: \.self) { kind in
                    Button { draft.kindOverride = kind } label: {
                        option(kind.title, isSelected: draft.kindOverride == kind)
                    }
                }
            } label: {
                menuRow("Тип цели", value: current.title, isMuted: draft.kindOverride == nil)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Тип цели: \(current.title)")
            .accessibilityIdentifier("goal.kind")
            Text("Linea определяет тип сама: по нему она предложила, как считать прогресс, и стадии цели.")
                .font(LineaFont.caption)
                .foregroundStyle(LineaColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Удалить

    private var deleteButton: some View {
        Button(role: .destructive) {
            guard !isSaving else { return }
            isSaving = true
            Task {
                await plan.deleteGoal(existing)
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

    // MARK: Помощники

    @ViewBuilder
    private func option(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private var trimmedTitle: String {
        draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        var result = edited
        result.title = trimmedTitle
        result.targetState = Self.text(targetState)
        result.successCriteria = criteria
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // Пустые этапы и числа без цели — не этапы и не числа.
        result.milestones = draft.milestones
            .map { milestone in
                var milestone = milestone
                milestone.title = milestone.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !showsWeights { milestone.weight = nil }
                return milestone
            }
            .filter { !$0.title.isEmpty }
        result.metrics = draft.metrics.filter { metric in
            !(metric.unit.trimmingCharacters(in: .whitespaces).isEmpty && metric.target == metric.start)
        }
        if result.isCompleted { result.progress = 1 }
        Task {
            await plan.saveGoal(result)
            dismiss()
        }
    }

    private static func text(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
