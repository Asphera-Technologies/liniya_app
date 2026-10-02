//
//  GoalIntakeView.swift
//  Linea
//
//  «Новая цель»: сначала Linea понимает цель, потом цель создаётся.
//    1. «Чего хочешь достичь?» — единственное обязательное поле; ниже
//       «Расскажи подробнее» текстом или «Рассказать голосом».
//    2. Если без этого цель не понять — один вопрос, его можно пропустить.
//    3. «Я поняла цель так»: название, «Сейчас», «Результат» — «Всё верно»
//       или «Изменить».
//  Понимает ядро (`GoalAnalyzing`), экран только показывает.
//

import SwiftUI

struct GoalIntakeView: View {
    @Environment(GoalIntakeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case title, details, answer
    }

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            ScrollView {
                Group {
                    switch store.step {
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
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(store.dictation.phase != .idle || store.step != .describe)
        .onAppear {
            store.begin()
            focus = .title
        }
        .onDisappear { store.end() }
    }

    private var navigationTitle: String {
        switch store.step {
        case .describe: return "Новая цель"
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
    }

    // MARK: 2. Вопрос

    private func ask(_ question: GoalQuestion) -> some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 16) {
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
                    if let deadline = understanding.deadline {
                        Text("Срок — \(RussianText.shortDay(deadline, time: store.time).lowercased())")
                            .font(LineaFont.caption)
                            .foregroundStyle(LineaColor.textSecondary)
                    }
                }
                part("Сейчас", understanding.currentState, identifier: "goal.review.current")
                part("Результат", understanding.targetState, identifier: "goal.review.target")
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
