//
//  InboxReviewView.swift
//  Linea
//
//  «Разобрать» «Без даты»: по одной задаче. Название, подсказка Linea, куда
//  её и почему, и короткий выбор — Сегодня / Завтра / На неделе / Оставить
//  без даты, ниже «Удалить». Подсказанный вариант залит чёрным. Разобрали
//  последнюю — лист закрывается. Подсказка и её текст — из ядра
//  (`InboxReview`), экран только показывает.
//

import SwiftUI

/// Что разбирать: только неразобранные (предложение на «Сегодня») или всё
/// «Без даты» («Разобрать» в «Плане»).
enum InboxReviewScope: String, Identifiable {
    case unsorted
    case all

    var id: String { rawValue }
}

struct InboxReviewView: View {
    let scope: InboxReviewScope

    @Environment(\.dismiss) private var dismiss
    @Environment(PlanStore.self) private var plan
    @Environment(IntelligenceStore.self) private var intelligence
    @Environment(UserProfileStore.self) private var profile

    /// Очередь фиксируется при открытии: задача, отправленная в «Сегодня»,
    /// уходит из «Без даты», а счёт «2 из 5» не прыгает.
    @State private var queue: [UUID] = []
    @State private var position = 0
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let task = currentTask {
                    card(task)
                        .id(task.id)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .opacity))
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Без даты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .onAppear(perform: start)
    }

    private var currentTask: LineaTask? {
        guard queue.indices.contains(position) else { return nil }
        return plan.tasks.first { $0.id == queue[position] }
    }

    // MARK: Карточка

    private func card(_ task: LineaTask) -> some View {
        let suggestion = InboxReview().suggestion(
            for: task, goals: plan.goals,
            plannedStart: intelligence.plannedStart(for: task.id), time: intelligence.time
        )
        return VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(position + 1) из \(queue.count)")
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textTertiary)
                Text(task.title)
                    .font(LineaFont.feature)
                    .foregroundStyle(LineaColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inbox.title")
                Label(suggestion.reason, systemImage: "sparkles")
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inbox.suggestion")
            }

            VStack(spacing: 10) {
                ForEach(InboxReview.Choice.allCases, id: \.self) { choice in
                    choiceButton(choice, isSuggested: choice == suggestion.choice) {
                        sort(task, as: choice)
                    }
                    .accessibilityIdentifier("inbox.choice.\(choice.rawValue)")
                }
            }
            .disabled(isWorking)

            Button(role: .destructive) {
                delete(task)
            } label: {
                Text("Удалить")
                    .font(LineaFont.control)
                    .padding(.vertical, 6)
            }
            .disabled(isWorking)
            .accessibilityIdentifier("inbox.delete")
        }
        .padding(.horizontal, LineaMetrics.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private func choiceButton(_ choice: InboxReview.Choice, isSuggested: Bool, action: @escaping () -> Void) -> some View {
        if isSuggested {
            LineaPrimaryButton(title: choice.title, fillsWidth: true, action: action)
                .accessibilityHint("Подсказка Linea")
        } else {
            LineaOutlineButton(title: choice.title, fillsWidth: true, action: action)
        }
    }

    // MARK: Действия

    private func start() {
        guard queue.isEmpty else { return }
        let unsorted = InboxReview.unsorted(plan.tasks)
        let kept = InboxReview.inbox(plan.tasks).filter { $0.inboxReviewedAt != nil }
        queue = (scope == .unsorted ? unsorted : unsorted + kept).map(\.id)
        if queue.isEmpty { dismiss() }
    }

    private func sort(_ task: LineaTask, as choice: InboxReview.Choice) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            await plan.sortInboxTask(task, as: choice, profile: profile.profile)
            advance()
        }
    }

    private func delete(_ task: LineaTask) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            await plan.deleteTask(task)
            advance()
        }
    }

    private func advance() {
        isWorking = false
        guard position + 1 < queue.count else {
            dismiss()
            return
        }
        withAnimation(.snappy) { position += 1 }
    }
}
