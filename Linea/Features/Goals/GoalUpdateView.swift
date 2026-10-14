//
//  GoalUpdateView.swift
//  Linea
//
//  «Обновить состояние» из карточки цели (ADR-047):
//
//      Что изменилось?
//      [________________________________]
//      🎙 Рассказать
//
//  — и Linea показывает, как поняла: ✓ завершено, ● почти готово, ○ не
//  начато, числа, стадия и «Новый фокус». [Подтвердить] меняет цель,
//  [Изменить] возвращает к словам. Тексты строк — из ядра (`GoalStateUpdate`).
//

import SwiftUI

struct GoalUpdateView: View {
    let goal: LineaGoal
    /// Цель сохранена — карточка показывает её такой, какой она стала.
    var onConfirmed: (LineaGoal) -> Void

    @Environment(GoalUpdateStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let proposal = store.proposal {
                        proposalView(proposal)
                    } else {
                        input
                    }
                }
                .padding(.horizontal, LineaMetrics.screenPadding)
                .padding(.vertical, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(LineaColor.background.ignoresSafeArea())
            .navigationTitle("Обновить состояние")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }.tint(LineaColor.ink)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            store.begin(goal)
            isFocused = true
        }
        .onDisappear { store.end() }
    }

    // MARK: Что изменилось

    private var input: some View {
        @Bindable var store = store
        let phase = store.dictation.phase
        return VStack(alignment: .leading, spacing: 16) {
            Text("Что изменилось?")
                .font(LineaFont.feature)
                .foregroundStyle(LineaColor.textPrimary)
            LineaTextField(placeholder: "TestFlight уже сделали, onboarding почти готов…", text: $store.text,
                           axis: .vertical, font: LineaFont.rowTitle, identifier: "goal.update.text")
                .lineLimit(2...8)
                .focused($isFocused)
            Button {
                isFocused = false
                store.toggleDictation()
            } label: {
                HStack(spacing: 6) {
                    switch phase {
                    case .idle:
                        Image(systemName: "mic")
                        Text("Рассказать")
                    case .recording:
                        Image(systemName: "stop.fill")
                        Text("Закончить запись")
                    case .transcribing:
                        ProgressView().controlSize(.small)
                        Text("Распознаю…")
                    }
                }
                .font(LineaFont.caption)
                .foregroundStyle(phase == .recording ? LineaColor.onInk : LineaColor.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule(style: .continuous).fill(phase == .recording ? LineaColor.ink : LineaColor.fill))
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(phase == .transcribing)
            .accessibilityIdentifier("goal.update.voice")
            if let notice = store.dictation.notice {
                Text(notice)
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LineaPrimaryButton(title: "Разобрать", fillsWidth: true) {
                isFocused = false
                withAnimation(.snappy) { store.read() }
            }
            .disabled(!store.canRead)
            .accessibilityIdentifier("goal.update.read")
        }
    }

    // MARK: Как Linea поняла

    private func proposalView(_ proposal: GoalStateUpdate) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(text: "Обновлю состояние")
            VStack(alignment: .leading, spacing: 10) {
                if proposal.isEmpty {
                    Text("Этапов и чисел в словах не нашла — обновлю только «Что уже сделано».")
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(proposal.items) { item in
                    Text(GoalStateUpdate.line(item))
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(item.status == .notStarted ? LineaColor.textSecondary : LineaColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("goal.update.item")
                }
                ForEach(proposal.metrics, id: \.metricID) { change in
                    Text(GoalStateUpdate.line(change, goal: goal))
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textPrimary)
                        .accessibilityIdentifier("goal.update.metric")
                }
                if let stage = proposal.stage {
                    Text("Стадия — \(stage)")
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textPrimary)
                        .accessibilityIdentifier("goal.update.stage")
                }
            }
            if let focus = proposal.focusSentence {
                Text(focus)
                    .font(LineaFont.rowTitle)
                    .foregroundStyle(LineaColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("goal.update.focus")
            }
            FlowLayout(spacing: 12) {
                LineaPrimaryButton(title: "Подтвердить") {
                    Task {
                        if let saved = await store.confirm() {
                            onConfirmed(saved)
                            dismiss()
                        }
                    }
                }
                .disabled(store.isSaving)
                .accessibilityIdentifier("goal.update.confirm")
                LineaOutlineButton(title: "Изменить") {
                    withAnimation(.snappy) { store.edit() }
                }
                .accessibilityIdentifier("goal.update.edit")
            }
        }
    }
}
