//
//  TodayView.swift
//  Linea
//
//  The Today screen — the whole wow-scenario in one place:
//    • morning: what Linea sees about the state, the day's plan, «Принять план»;
//    • during the day: the nudge card with the same two answers the
//      notification offers, and «Сейчас» — what is reasonable to do this very
//      minute (the priority engine's action score), refreshed every minute;
//    • evening: «Как прошёл день?» — the check-in by voice or text, or three
//      quick taps, which close the feedback loop.
//
//  The screen composes; it never decides. Every string comes ready from the
//  core (`Recommendation.message`, `Nudge.title/body`), so what the user reads
//  here is exactly what the golden tests assert.
//

import SwiftUI

struct TodayView: View {
    @Environment(AppState.self) private var appState
    @Environment(PlanStore.self) private var plan
    @Environment(IntelligenceStore.self) private var intelligence
    /// «Другое» у «Сейчас» раскрыто.
    @State private var showsAlternatives = false
    /// Карточка задачи из «Дальше».
    @State private var editingTask: TaskEditTarget?
    /// Задача, для которой открыт выбор «Перенести».
    @State private var rescheduling: LineaTask?

    var body: some View {
        NavigationStack {
            LineaScaffold(title: greeting, subtitle: dateSubtitle) {
                if let nudge = intelligence.dueNudge {
                    NudgeCard(nudge: nudge) { action in
                        Task { await intelligence.respond(to: nudge, action: action) }
                    }
                }

                briefSection
                mainToday
                nowSection
                timeline
                inboxOffer

                if intelligence.isCheckInDue {
                    EveningReviewCard(
                        canRate: intelligence.canRateDay,
                        onTell: { appState.openCheckIn() },
                        onRate: { rating in Task { await intelligence.rateDay(rating) } }
                    )
                } else if let entry = intelligence.todayCheckIn {
                    CheckInSummaryCard(numbers: DayDigestBuilder().numbers(for: entry.report)) {
                        appState.openCheckIn()
                    }
                }

                adviceSection
            }
        }
        .task { await intelligence.refresh(reason: .appeared) }
        .task { await intelligence.keepNextActionFresh() }
        .refreshable { await intelligence.refresh(reason: .manual) }
        .sheet(item: $editingTask) { target in
            TaskEditorView(existing: target.task)
        }
        .taskRescheduleDialog($rescheduling)
    }

    // MARK: Brief

    @ViewBuilder
    private var briefSection: some View {
        if let brief = intelligence.brief {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "План на сегодня", trailing: intelligence.stateTag)
                Text(brief.message)
                    .font(LineaFont.feature)
                    .foregroundStyle(LineaColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let explanation = brief.explanation, !explanation.isEmpty {
                    Text(explanation)
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !intelligence.reasons.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(intelligence.reasons, id: \.self) { reason in
                            Text(reason)
                                .font(LineaFont.caption)
                                .foregroundStyle(LineaColor.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if intelligence.canAcceptPlan {
                    LineaOutlineButton(title: "Принять план") {
                        Task { await intelligence.acceptPlan() }
                    }
                }
            }
        }
    }

    // MARK: Main task

    private var mainToday: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Главное сегодня")
            if let task = intelligence.topTask ?? plan.topTaskToday {
                Text(task.title)
                    .font(LineaFont.feature)
                    .foregroundStyle(LineaColor.textPrimary)
            } else {
                Text("На сегодня задач нет")
                    .font(LineaFont.feature)
                    .foregroundStyle(LineaColor.textTertiary)
            }
        }
    }

    // MARK: Now

    /// «Сейчас»: одно действие — что, сколько и почему, [Начать] [Другое].
    /// «Другое» раскрывает два-три варианта, а не весь список задач. Начатое —
    /// «в работе» с [Готово]. Причина — одна короткая фраза, готовая в ядре
    /// (`NowReasoner`): у каждой рекомендации она есть.
    @ViewBuilder
    private var nowSection: some View {
        if let action = intelligence.nextAction {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Сейчас", trailing: action.isStarted ? "в работе" : nil)
                if let option = action.option {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(option.title)
                            .font(LineaFont.feature)
                            .foregroundStyle(LineaColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(QuickTaskText.duration(minutes: option.minutes))
                            .font(LineaFont.caption)
                            .foregroundStyle(LineaColor.textTertiary)
                    }
                } else {
                    Text(RussianTypography.nonBreaking(action.headline))
                        .font(LineaFont.feature)
                        .foregroundStyle(LineaColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(action.headline)
                }
                if !action.reason.isEmpty {
                    // Неразрывные пробелы: иначе «а» в конце строки сбивает
                    // подсчёт высоты, и причина обрезается многоточием.
                    Text(RussianTypography.nonBreaking(action.reason))
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(action.reason)
                }
                if action.option != nil {
                    HStack(spacing: 12) {
                        if action.isStarted {
                            LineaOutlineButton(title: "Готово") {
                                Task { await intelligence.finishAction() }
                            }
                        } else {
                            LineaOutlineButton(title: "Начать") {
                                Task { await intelligence.startAction() }
                            }
                        }
                        if !action.alternatives.isEmpty {
                            LineaOutlineButton(title: showsAlternatives ? "Скрыть" : "Другое") {
                                withAnimation(.snappy) { showsAlternatives.toggle() }
                            }
                        }
                    }
                }
                if showsAlternatives, !action.alternatives.isEmpty {
                    alternativesList(action.alternatives)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.now")
        }
    }

    /// «Можно ещё:» — два-три варианта; тап делает вариант действием «сейчас».
    private func alternativesList(_ options: [NextAction.Option]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Можно ещё:")
                .font(LineaFont.caption)
                .foregroundStyle(LineaColor.textSecondary)
                .padding(.bottom, 2)
            ForEach(options) { option in
                Button {
                    withAnimation(.snappy) { showsAlternatives = false }
                    intelligence.chooseAlternative(option)
                } label: {
                    HStack(spacing: 12) {
                        Text(option.title)
                            .font(LineaFont.rowTitle)
                            .foregroundStyle(LineaColor.textPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Text(QuickTaskText.duration(minutes: option.minutes))
                            .font(LineaFont.caption)
                            .foregroundStyle(LineaColor.textTertiary)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.title), \(QuickTaskText.duration(minutes: option.minutes))")
                if option.id != options.last?.id { LineaHairline() }
            }
        }
    }

    // MARK: Inbox

    /// «Без даты» накопилось — Linea предлагает разобрать за минуту. Текст и
    /// когда предлагать — из ядра (`InboxReview.offer`).
    @ViewBuilder
    private var inboxOffer: some View {
        if let offer = InboxReview().offer(tasks: plan.tasks, time: intelligence.time) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Без даты")
                Text(offer.text)
                    .font(LineaFont.rowTitle)
                    .foregroundStyle(LineaColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                LineaOutlineButton(title: "Разобрать") { appState.openInboxReview(.unsorted) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.inbox")
        }
    }

    // MARK: Timeline

    @ViewBuilder
    private var timeline: some View {
        let blocks = intelligence.visibleBlocks
        if !blocks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Дальше", trailing: intelligence.planTag)
                VStack(spacing: 0) {
                    ForEach(blocks) { block in
                        // Задача в плане — те же свайпы и меню, что в «Плане»;
                        // тап открывает её карточку. Еда и встречи — как есть.
                        if let task = block.taskID.flatMap({ id in plan.tasks.first { $0.id == id } }) {
                            let actions = rowActions(for: task)
                            PlanBlockRow(
                                block: block,
                                time: intelligence.time,
                                isDone: task.isDone,
                                onTap: { editingTask = .edit(task) }
                            )
                            .taskAccessibilityActions(actions, for: task)
                            .taskActions(actions, for: task)
                        } else {
                            PlanBlockRow(
                                block: block,
                                time: intelligence.time,
                                isDone: intelligence.isDone(block)
                            )
                        }
                    }
                }
            }
        }
    }

    /// Свайп вправо — «Готово», влево — «Перенести», долгое нажатие — меню.
    private func rowActions(for task: LineaTask) -> TaskRowActions {
        plan.rowActions(
            for: task,
            onEdit: { editingTask = .edit(task) },
            onReschedule: { rescheduling = task }
        )
    }

    // MARK: Advice (nutrition and the like)

    @ViewBuilder
    private var adviceSection: some View {
        let advice = intelligence.advice
        if !advice.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(text: "Советы")
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(advice) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.message)
                                .font(LineaFont.rowTitle)
                                .foregroundStyle(LineaColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !item.actions.isEmpty {
                                HStack(spacing: 12) {
                                    ForEach(Array(item.actions.enumerated()), id: \.offset) { _, action in
                                        if let title = actionTitle(action) {
                                            LineaOutlineButton(title: title) {
                                                Task { await intelligence.perform(action) }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func actionTitle(_ action: RecommendationAction) -> String? {
        switch action {
        case .markMealEaten: return "Поел"
        case .openTask: return "Открыть"
        case .deferTask: return "Перенести"
        case .acceptPlan, .dismiss: return nil
        }
    }

    // MARK: Greeting

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Доброе утро"
        case 12..<18: return "Добрый день"
        case 18..<23: return "Добрый вечер"
        default: return "Доброй ночи"
        }
    }

    private var dateSubtitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEE, d"
        return formatter.string(from: Date()).capitalizedFirst
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
