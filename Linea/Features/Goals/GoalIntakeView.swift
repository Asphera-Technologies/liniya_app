//
//  GoalIntakeView.swift
//  Linea
//
//  «Новая цель». Сначала — быстрая цель (`QuickGoalView`): одна строка,
//  чипы, «Создать цель» (ADR-035). По желанию — «Рассказать подробнее»:
//    1. «Чего хочешь достичь?» и «Расскажи подробнее» текстом или голосом;
//    2. если без этого цель не понять — один вопрос, его можно пропустить;
//    3. «Я поняла цель так»: название, срок, «Сейчас», «Результат», как
//       считать прогресс — «Всё верно» или «Изменить».
//  Понимает ядро (`QuickGoalDraft`, `GoalAnalyzing`), экран только показывает.
//

import SwiftUI

struct GoalIntakeView: View {
    @Environment(GoalIntakeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?
    /// Быстрая цель — невысокий лист по содержимому, как у быстрой задачи.
    @State private var quickHeight: CGFloat = 260
    @Namespace private var ownerSegments

    private enum Field: Hashable {
        case title, details, answer
    }

    var body: some View {
        ZStack {
            if store.step == .quick {
                QuickGoalView(onClose: { dismiss() }, onCreated: { dismiss() }, onHeight: { quickHeight = $0 })
            } else {
                flow
            }
        }
        .background(LineaColor.background.ignoresSafeArea())
        .presentationDetents(store.step == .quick ? [.height(max(quickHeight, 220))] : [.large])
        .presentationDragIndicator(store.step == .quick ? .hidden : .visible)
        .interactiveDismissDisabled(store.dictation.phase != .idle || !(store.step == .quick || store.step == .describe))
        .onAppear { store.begin() }
        .onDisappear { store.end() }
    }

    /// Подробно: рассказ, вопрос, «Я поняла цель так», «Изменить».
    private var flow: some View {
        @Bindable var store = store

        return NavigationStack {
            ScrollView {
                Group {
                    switch store.step {
                    case .quick: EmptyView()
                    case .describe: describe
                    case .question(let question): ask(question)
                    case .review: review
                    case .edit: edit
                    }
                }
                .padding(.horizontal, LineaMetrics.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(LineaColor.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { actions }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }.tint(LineaColor.ink)
                }
            }
        }
    }

    private var navigationTitle: String {
        switch store.step {
        case .quick, .describe: return "Новая цель"
        case .question: return "Уточню одно"
        case .review, .edit: return "Новая цель"
        }
    }

    // MARK: 1. Рассказ

    private var describe: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Чего хочешь достичь?")
                LineaTextField(placeholder: "Например, запустить закрытую beta Linea", text: $store.title, axis: .vertical,
                               identifier: "goal.title")
                    .focused($focus, equals: .title)
                    .submitLabel(.next)
            }
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Расскажи подробнее", trailing: "необязательно")
                Text("Что уже сделано, где ты сейчас и что будет означать, что цель достигнута?")
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                LineaTextField(placeholder: "Например: у нас уже есть приложение…", text: $store.details,
                               axis: .vertical, font: LineaFont.rowTitle, identifier: "goal.details")
                    .lineLimit(3...10)
                    .focused($focus, equals: .details)
                voiceButton(idle: "Рассказать голосом")
                voiceStatus
            }
        }
        // Из быстрой цели название уже есть — сразу к рассказу.
        .onAppear { focus = store.title.isEmpty ? .title : .details }
    }

    // MARK: 2. Вопрос

    private func ask(_ question: GoalQuestion) -> some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 16) {
            if question.topic == .owner {
                // Linea увидела в словах команду или компанию — и спрашивает,
                // так ли это, прежде чем спросить про свою часть.
                VStack(alignment: .leading, spacing: 10) {
                    Text("Эта цель зависит только от тебя или от команды?")
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    LineaSegmentedControl(
                        options: [GoalScope.personal.choiceTitle, GoalScope.team.choiceTitle],
                        selection: Binding(
                            get: { 1 },
                            set: { index in
                                if index == 0 { Task { await store.answerPersonal() } }
                            }
                        ),
                        namespace: ownerSegments
                    )
                    .accessibilityIdentifier("goal.owner.scope")
                }
            }
            Text(question.text)
                .font(LineaFont.feature)
                .foregroundStyle(LineaColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("goal.question")
            Text(question.example)
                .font(LineaFont.caption)
                .foregroundStyle(LineaColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            LineaTextField(placeholder: "Ответ", text: $store.answer, axis: .vertical, font: LineaFont.rowTitle,
                           identifier: "goal.answer")
                .lineLimit(2...8)
                .focused($focus, equals: .answer)
            voiceButton(idle: "Ответить голосом")
            voiceStatus
        }
        .onAppear { focus = .answer }
    }

    // MARK: 3. «Я поняла цель так»

    @ViewBuilder
    private var review: some View {
        if let understanding = store.understanding {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Я поняла цель так")
                    Text(understanding.title)
                        .font(LineaFont.feature)
                        .foregroundStyle(LineaColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("goal.review.title")
                    let summary = reviewSummary(understanding)
                    if !summary.isEmpty {
                        Text(summary)
                            .font(LineaFont.caption)
                            .foregroundStyle(LineaColor.textSecondary)
                            .accessibilityIdentifier("goal.review.summary")
                    }
                }
                if understanding.scope.isShared {
                    part("Моя часть", understanding.ownerScope, identifier: "goal.review.part")
                }
                part("Сейчас", understanding.currentState, identifier: "goal.review.current")
                part("Результат", understanding.targetState, identifier: "goal.review.target")
                progressPart(understanding)
                let extra = extraCriteria(understanding)
                if !extra.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Как поймём, что получилось")
                        ForEach(extra, id: \.self) { criterion in
                            Text("• \(criterion)")
                                .font(LineaFont.rowTitle)
                                .foregroundStyle(LineaColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("goal.review")
        }
    }

    private func part(_ label: String, _ text: String?, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: label)
            Text(text ?? "Пока не знаю — можно дописать в «Изменить».")
                .font(LineaFont.rowTitle)
                .foregroundStyle(text == nil ? LineaColor.textTertiary : LineaColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
        }
    }

    /// Срок, важность и чья цель — как у быстрой цели: «до 15 октября ·
    /// Высокая · цель компании».
    private func reviewSummary(_ understanding: GoalUnderstanding) -> String {
        var parts: [String] = []
        if let deadline = understanding.deadline { parts.append(GoalProgressText.deadline(deadline, time: store.time)) }
        if understanding.isPrioritySaid { parts.append(LineaGoal.importanceTitle(understanding.priority)) }
        if understanding.scope.isShared { parts.append("цель \(understanding.scope.title.lowercased())") }
        return parts.joined(separator: GoalProgressText.separator)
    }

    /// Как Linea будет считать прогресс — и что она для этого нашла в словах:
    /// этапы, числа, стадию.
    private func progressPart(_ understanding: GoalUnderstanding) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Прогресс", trailing: understanding.method.title)
            if understanding.method == .milestones || understanding.method == .hybrid {
                ForEach(understanding.milestones) { milestone in
                    Text("○ \(milestone.title)")
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if understanding.method == .metric || understanding.method == .hybrid {
                ForEach(understanding.metrics) { metric in
                    Text(GoalProgressText.metric(metric))
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textPrimary)
                }
            }
            if let stage = understanding.stage {
                Text("Стадия — \(stage)")
                    .font(LineaFont.rowTitle)
                    .foregroundStyle(LineaColor.textPrimary)
                    .accessibilityIdentifier("goal.review.stage")
            }
            Text(understanding.method.explanation)
                .font(LineaFont.caption)
                .foregroundStyle(LineaColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Признаки, которых нет в «Результате» дословно, — отдельным списком.
    private func extraCriteria(_ understanding: GoalUnderstanding) -> [String] {
        let target = RussianWords.normalized(understanding.targetState ?? "")
        return understanding.successCriteria.filter { !target.contains(RussianWords.normalized($0)) }
    }

    // MARK: «Изменить»

    private var edit: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Цель")
                LineaTextField(placeholder: "Чего хочешь достичь", text: $store.edits.title, axis: .vertical,
                               identifier: "goal.edit.title")
            }
            if store.understanding?.scope.isShared == true {
                editField("Моя часть", placeholder: "За какую часть отвечаешь ты", text: $store.edits.ownerScope)
            }
            editField("Сейчас", placeholder: "С чего начинаем", text: $store.edits.currentState)
            editField("Результат", placeholder: "Что будет, когда цель достигнута", text: $store.edits.targetState)
            editField("Как поймём, что получилось", placeholder: "По одному признаку на строку", text: $store.edits.criteria)
            VStack(spacing: 0) {
                Toggle(isOn: $store.edits.hasDeadline.animation(.snappy)) {
                    Text("Срок")
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textPrimary)
                }
                .tint(LineaColor.ink)
                .padding(.vertical, 12)
                if store.edits.hasDeadline {
                    DatePicker("Срок", selection: $store.edits.deadline, in: store.time.today..., displayedComponents: .date)
                        .tint(LineaColor.ink)
                        .padding(.bottom, 8)
                }
                LineaHairline()
            }
        }
    }

    private func editField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: label)
            LineaTextField(placeholder: placeholder, text: text, axis: .vertical, font: LineaFont.rowTitle)
                .lineLimit(1...8)
        }
    }

    // MARK: Кнопки внизу

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            switch store.step {
            case .quick:
                EmptyView()
            case .describe:
                LineaPrimaryButton(title: "Продолжить", fillsWidth: true) {
                    Task { await store.proceed() }
                }
                .disabled(!store.canContinue)
                .accessibilityIdentifier("goal.continue")
            case .question:
                LineaPrimaryButton(title: "Продолжить", fillsWidth: true) {
                    Task { await store.answerQuestion() }
                }
                .disabled(!store.canAnswer)
                .accessibilityIdentifier("goal.answer.continue")
                Button("Пропустить") {
                    Task { await store.skipQuestion() }
                }
                .font(LineaFont.control)
                .tint(LineaColor.textSecondary)
                .accessibilityIdentifier("goal.skip")
            case .review:
                HStack(spacing: 12) {
                    LineaPrimaryButton(title: "Всё верно", fillsWidth: true) {
                        Task { if await store.confirm() { dismiss() } }
                    }
                    .disabled(store.isSaving)
                    .accessibilityIdentifier("goal.confirm")
                    LineaOutlineButton(title: "Изменить", fillsWidth: true) {
                        store.startEditing()
                    }
                    .accessibilityIdentifier("goal.change")
                }
            case .edit:
                LineaPrimaryButton(title: "Готово", fillsWidth: true) {
                    store.finishEditing()
                }
                .disabled(store.edits.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("goal.edit.done")
            }
        }
        .padding(.horizontal, LineaMetrics.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(LineaColor.background)
    }

    // MARK: Голос

    private func voiceButton(idle: String) -> some View {
        Button {
            focus = nil
            store.dictation.toggle()
        } label: {
            HStack(spacing: 8) {
                switch store.dictation.phase {
                case .idle:
                    Image(systemName: "mic")
                    Text(idle)
                case .recording:
                    Image(systemName: "stop.fill")
                    Text("Закончить запись")
                case .transcribing:
                    ProgressView().controlSize(.small)
                    Text("Распознаю на телефоне…")
                }
            }
            .font(LineaFont.control)
            .foregroundStyle(store.dictation.phase == .recording ? LineaColor.onInk : LineaColor.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: LineaMetrics.controlRadius, style: .continuous)
                    .fill(store.dictation.phase == .recording ? LineaColor.ink : LineaColor.fill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.dictation.phase == .transcribing)
        .accessibilityIdentifier("goal.voice")
    }

    @ViewBuilder
    private var voiceStatus: some View {
        if store.dictation.phase == .recording {
            Text("Слушаю · \(Self.clock(store.dictation.recorder.elapsed)). Говори как есть — Linea разберёт.")
                .font(LineaFont.caption)
                .foregroundStyle(LineaColor.textSecondary)
        } else if let notice = store.dictation.notice {
            Text(notice)
                .font(LineaFont.caption)
                .foregroundStyle(LineaColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if store.isThinking {
            Text("Разбираю…")
                .font(LineaFont.caption)
                .foregroundStyle(LineaColor.textSecondary)
        }
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
