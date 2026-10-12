//
//  GoalProgressEditor.swift
//  Linea
//
//  Прогресс в карточке цели — по её методу (ADR-037): число («Было»,
//  «Сейчас», «Цель», «Что считаем»), этапы (кружок — закрыть, ввод — следующий
//  этап, веса — по желанию), этапы и числа со «Следующим рубежом», «отмечаю
//  сам» (четыре капсулы) или без процентов (стадия, последнее продвижение,
//  значимые действия за 30 дней). Сверху — меню метода: Linea выбрала его при
//  создании, человек меняет. Правит цель карточки (`GoalEditorView`);
//  прогресс считает ядро (`GoalProgressEngine`).
//

import SwiftUI

struct GoalProgressEditor: View {
    @Binding var goal: LineaGoal
    /// Прогресс цели так, как она сохранится.
    let progress: GoalProgress
    let time: TimeContext
    /// Веса этапов видны, если они уже есть или человек их включил.
    @Binding var showsWeights: Bool

    /// Этап, который сейчас набирают: «+ этап» и ввод сразу ставят курсор в новый.
    @FocusState private var focusedMilestone: UUID?

    // MARK: Прогресс

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Прогресс")
                    .font(LineaFont.sectionLabel)
                    .foregroundStyle(LineaColor.textSecondary)
                Spacer(minLength: 8)
                methodMenu
            }
            if !(goal.progressMethod == .qualitative && !goal.isCompleted) {
                Text(GoalProgressText.summary(progress, time: time))
                    .font(LineaFont.rowTitle)
                    .foregroundStyle(LineaColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("goal.progress.summary")
                GoalProgressBar(progress: progress)
            }
            switch goal.progressMethod {
            case .metric:
                metricsEditor(limit: 1)
            case .milestones:
                milestonesEditor(progress)
            case .hybrid:
                milestonesEditor(progress)
                metricsEditor(limit: nil)
            case .manual:
                manualSelector
            case .qualitative:
                qualitativeBlock(progress)
            }
            Text(goal.progressMethod.explanation)
                .font(LineaFont.caption)
                .foregroundStyle(LineaColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Как считать прогресс: Linea выбрала при создании, человек меняет.
    private var methodMenu: some View {
        Menu {
            ForEach(GoalProgressMethod.allCases, id: \.self) { method in
                Button {
                    withAnimation(.snappy) { goal.progressMethod = method }
                } label: {
                    option(method.title, isSelected: goal.progressMethod == method)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(goal.progressMethod.title)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(LineaFont.sectionLabel)
            .foregroundStyle(LineaColor.textPrimary)
        }
        .accessibilityLabel("Как считать прогресс: \(goal.progressMethod.title)")
        .accessibilityIdentifier("goal.method")
    }

    // MARK: Этапы

    private func milestonesEditor(_ progress: GoalProgress) -> some View {
        let next = goal.nextMilestone?.id
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(goal.milestones) { milestone in
                milestoneRow(milestone, isNext: milestone.id == next)
                LineaHairline()
            }
            Button {
                addMilestone(after: nil)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.footnote.weight(.medium))
                    Text(goal.milestones.isEmpty ? "Крупный этап" : "Ещё этап")
                        .font(LineaFont.rowTitle)
                }
                .foregroundStyle(LineaColor.textTertiary)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("goal.milestone.add")
            if goal.progressMethod == .hybrid, let next = progress.nextMilestone, !next.title.isEmpty {
                Text("Следующий рубеж — \(next.title)")
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textSecondary)
                    .padding(.bottom, 6)
            }
            if !goal.milestones.isEmpty {
                Toggle(isOn: $showsWeights.animation(.snappy)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Веса этапов")
                            .font(LineaFont.rowTitle)
                            .foregroundStyle(LineaColor.textPrimary)
                        Text("Процент — только когда вес есть у каждого этапа.")
                            .font(LineaFont.caption)
                            .foregroundStyle(LineaColor.textTertiary)
                    }
                }
                .tint(LineaColor.ink)
                .padding(.vertical, 8)
            }
        }
    }

    private func milestoneRow(_ milestone: GoalMilestone, isNext: Bool) -> some View {
        let binding = milestoneBinding(milestone.id)
        return HStack(spacing: 12) {
            Button {
                withAnimation(.snappy) {
                    binding.wrappedValue.completedAt = milestone.isDone ? nil : time.now
                }
            } label: {
                Image(systemName: milestone.isDone ? "checkmark.circle.fill" : (isNext ? "circle.inset.filled" : "circle"))
                    .font(.title3)
                    .foregroundStyle(milestone.isDone || isNext ? LineaColor.ink : LineaColor.textTertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(milestone.isDone ? "Этап закрыт: \(milestone.title)" : "Закрыть этап «\(milestone.title)»")
            .accessibilityIdentifier("goal.milestone.toggle")

            TextField("Новый этап", text: binding.title, axis: .vertical)
                .font(LineaFont.rowTitle)
                .foregroundStyle(milestone.isDone ? LineaColor.textSecondary : LineaColor.textPrimary)
                .tint(LineaColor.ink)
                .focused($focusedMilestone, equals: milestone.id)
                .submitLabel(.next)
                .accessibilityIdentifier("goal.milestone.title")
                .onChange(of: milestone.title) { _, value in
                    // Ввод в многострочном поле — перевод строки; здесь это «следующий этап».
                    guard value.contains("\n") else { return }
                    binding.wrappedValue.title = value.replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespaces)
                    if binding.wrappedValue.title.isEmpty {
                        focusedMilestone = nil
                    } else {
                        addMilestone(after: milestone.id)
                    }
                }

            if showsWeights {
                LineaNumberField(label: "Вес", value: binding.weight, placeholder: "—", identifier: "goal.milestone.weight")
                    .frame(width: 56)
            }

            Button {
                withAnimation(.snappy) { goal.milestones.removeAll { $0.id == milestone.id } }
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(LineaColor.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Убрать этап «\(milestone.title)»")
        }
        .padding(.vertical, 10)
    }

    /// Новый пустой этап — после этого (или в конце) — и курсор в него.
    private func addMilestone(after id: UUID?) {
        let milestone = GoalMilestone(id: UUID(), title: "")
        withAnimation(.snappy) {
            if let id, let index = goal.milestones.firstIndex(where: { $0.id == id }) {
                goal.milestones.insert(milestone, at: index + 1)
            } else {
                goal.milestones.append(milestone)
            }
        }
        Task {
            // Поле появится в следующем проходе раскладки — тогда и фокус.
            try? await Task.sleep(for: .milliseconds(80))
            focusedMilestone = milestone.id
        }
    }

    /// По id, а не по индексу: удалённый этап не уронит строку, которая
    /// ещё рисуется.
    private func milestoneBinding(_ id: UUID) -> Binding<GoalMilestone> {
        Binding(
            get: { goal.milestones.first { $0.id == id } ?? GoalMilestone(id: id, title: "") },
            set: { value in
                guard let index = goal.milestones.firstIndex(where: { $0.id == id }) else { return }
                goal.milestones[index] = value
            }
        )
    }

    // MARK: Числа

    @ViewBuilder
    private func metricsEditor(limit: Int?) -> some View {
        let shown = limit.map { Array(goal.metrics.prefix($0)) } ?? goal.metrics
        VStack(alignment: .leading, spacing: 18) {
            ForEach(shown) { metric in
                metricRow(metric, removable: limit == nil)
            }
            if limit == nil || goal.metrics.isEmpty {
                Button {
                    withAnimation(.snappy) {
                        goal.metrics.append(GoalMetric(id: UUID(), unit: "", target: 0))
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.footnote.weight(.medium))
                        Text(goal.metrics.isEmpty ? "Что считаем" : "Ещё число")
                            .font(LineaFont.rowTitle)
                    }
                    .foregroundStyle(LineaColor.textTertiary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("goal.metric.add")
            }
        }
    }

    private func metricRow(_ metric: GoalMetric, removable: Bool) -> some View {
        let binding = metricBinding(metric.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 12) {
                LineaTextField(placeholder: "Что считаем: пользователей, км, ₽", text: binding.unit, font: LineaFont.rowTitle,
                               identifier: "goal.metric.unit")
                if removable {
                    Button {
                        withAnimation(.snappy) { goal.metrics.removeAll { $0.id == metric.id } }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(LineaColor.textTertiary)
                            .padding(.bottom, 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Убрать число")
                }
            }
            // Значение меняется на каждый символ: «18» и сразу «Готово» — сохранится 18.
            HStack(alignment: .top, spacing: 16) {
                LineaNumberField(label: "Было", value: binding.start, identifier: "goal.metric.start")
                LineaNumberField(label: "Сейчас", value: binding.current, identifier: "goal.metric.current")
                LineaNumberField(label: "Цель", value: binding.target, identifier: "goal.metric.target")
            }
        }
    }

    private func metricBinding(_ id: UUID) -> Binding<GoalMetric> {
        Binding(
            get: { goal.metrics.first { $0.id == id } ?? GoalMetric(id: id, unit: "", target: 0) },
            set: { value in
                guard let index = goal.metrics.firstIndex(where: { $0.id == id }) else { return }
                goal.metrics[index] = value
            }
        )
    }

    // MARK: Отмечаю сам

    private var manualSelector: some View {
        let current = goal.reportedState
        return FlowLayout(spacing: 8) {
            ForEach(GoalManualState.allCases, id: \.self) { state in
                let isSelected = current == state
                Button {
                    withAnimation(.snappy) {
                        goal.manualState = state
                        // «Готово» — цель достигнута.
                        if state == .done { goal.isCompleted = true }
                    }
                } label: {
                    Text(state.title)
                        .font(LineaFont.control)
                        .foregroundStyle(isSelected ? LineaColor.onInk : LineaColor.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule(style: .continuous).fill(isSelected ? LineaColor.ink : LineaColor.fill))
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                .accessibilityIdentifier("goal.manual.\(state.rawValue)")
            }
        }
    }

    // MARK: Без процентов

    private func qualitativeBlock(_ progress: GoalProgress) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(GoalProgressText.qualitativeLines(progress, time: time), id: \.label) { line in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(line.label)
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textSecondary)
                    Spacer(minLength: 8)
                    Text(line.value)
                        .font(LineaFont.rowValue)
                        .foregroundStyle(LineaColor.textPrimary)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 10)
                LineaHairline()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("goal.qualitative")
    }

    @ViewBuilder
    private func option(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}
