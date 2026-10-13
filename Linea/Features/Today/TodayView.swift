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
                goalOfferSection
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
        .onDisappear { intelligence.clearTodayNotes() }
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

    /// «Сейчас»: одно действие — что, сколько и почему, [Начать] [Не сейчас]
    /// [Другое]. «Другое» раскрывает два-три варианта, а не весь список задач.
    /// Начатое — «в работе» с [Завершить] [Не сейчас] [Развернуть] (фокус).
    /// Причина — одна короткая фраза, готовая в ядре (`NowReasoner`): у каждой
    /// рекомендации она есть. Над действием — короткий ответ Linea на
    /// «Завершить» и «Не сейчас»: «Сделано за 35 мин.», «Хорошо, подберу другое.»
    @ViewBuilder
    private var nowSection: some View {
        if let action = intelligence.nextAction {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Сейчас", trailing: action.isStarted ? "в работе" : nil)
                nowNote
                notNowQuestion
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
                    WrappingText(
                        text: RussianTypography.nonBreaking(action.headline),
                        textStyle: .title2,
                        color: LineaColor.textPrimary,
                        accessibilityText: action.headline
                    )
                }
                if !action.reason.isEmpty {
                    // UILabel, а не Text: SwiftUI мерил длинную причину на
                    // строку короче, чем рисовал, и обрезал её многоточием.
                    WrappingText(
                        text: RussianTypography.nonBreaking(action.reason),
                        textStyle: .body,
                        color: LineaColor.textSecondary,
                        accessibilityText: action.reason
                    )
                }
                if action.option != nil {
                    // Три кнопки на узком экране или крупным шрифтом не влезают
                    // в строку — переносятся.
                    FlowLayout(spacing: 12) {
                        if action.isStarted {
                            LineaOutlineButton(title: "Завершить") {
                                Task { await intelligence.finishAction() }
                            }
                        } else {
                            LineaOutlineButton(title: "Начать") {
                                Task { await intelligence.startAction() }
                            }
                        }
                        LineaOutlineButton(title: "Не сейчас") {
                            showsAlternatives = false
                            Task { await intelligence.notNowAction() }
                        }
                        // У начатого «Другое» нет: взяться за другое — «Не
                        // сейчас» или «Начать» в списке. Зато можно вернуться
                        // в фокус, если его свернули.
                        if action.isStarted, let taskID = action.taskID {
                            LineaOutlineButton(title: "Развернуть") {
                                intelligence.openFocus(taskID)
                            }
                            .accessibilityIdentifier("now.openFocus")
                        } else if !action.alternatives.isEmpty {
                            LineaOutlineButton(title: showsAlternatives ? "Скрыть" : "Другое") {
                                withAnimation(.snappy) { showsAlternatives.toggle() }
                            }
                        }
                    }
                }
                if showsAlternatives, !action.isStarted, !action.alternatives.isEmpty {
                    alternativesList(action.alternatives)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.now")
        } else if intelligence.nowNote != nil {
            // Сделал последнее — предлагать нечего, но ответ Linea виден.
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Сейчас")
                nowNote
                notNowQuestion
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.now")
        }
    }

    /// «Сделано за 35 мин.», «Хорошо, подберу другое.» — тихо, одной строкой.
    /// После «Неактуально» рядом — «Вернуть».
    @ViewBuilder
    private var nowNote: some View {
        if let note = intelligence.nowNote {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(LineaColor.textSecondary)
                        .accessibilityHidden(true)
                    Text(note)
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("now.note")
                if intelligence.canRestoreRemovedTask {
                    Spacer(minLength: 8)
                    Button("Вернуть") {
                        Task { await intelligence.restoreRemovedTask() }
                    }
                    .font(LineaFont.control)
                    .tint(LineaColor.textPrimary)
                    .accessibilityIdentifier("now.restore")
                }
            }
        }
    }

    /// «Почему не сейчас?» — иногда, компактно: четыре ответа капсулами.
    /// Отвечать не обязательно: вопрос уйдёт сам, когда закроешь «Сегодня».
    @ViewBuilder
    private var notNowQuestion: some View {
        if let question = intelligence.notNowQuestion {
            VStack(alignment: .leading, spacing: 8) {
                Text(question.title)
                    .font(LineaFont.rowTitle)
                    .foregroundStyle(LineaColor.textPrimary)
                FlowLayout(spacing: 8) {
                    ForEach(question.reasons, id: \.self) { reason in
                        Button {
                            Task { await intelligence.answerNotNow(reason) }
                        } label: {
                            Text(reason.title)
                                .font(LineaFont.control)
                                .foregroundStyle(LineaColor.textPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(Capsule(style: .continuous).fill(LineaColor.fill))
                                .contentShape(Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("notNow.\(reason.rawValue)")
                    }
                }
            }
            .padding(.bottom, 6)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("now.question")
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
                    Task { await intelligence.chooseAlternative(option) }
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

    // MARK: Goals

    /// Мягкая поддержка целей — вопрос, а не упрёк: окно для цели среди
    /// текущих дел или цель, которая давно не двигалась. Тексты — из ядра
    /// (`GoalBalance`, `GoalAttention`).
    @ViewBuilder
    private var goalOfferSection: some View {
        if let confirmation = intelligence.goalOfferConfirmation {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(LineaColor.textSecondary)
                    .accessibilityHidden(true)
                Text(confirmation)
                    .font(LineaFont.rowTitle)
                    .foregroundStyle(LineaColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("today.goalOffer.done")
        } else if let offer = intelligence.goalOffer {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Цели")
                VStack(alignment: .leading, spacing: 4) {
                    Text(offer.observation)
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(offer.question)
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail = offer.detail {
                    Text(detail)
                        .font(LineaFont.caption)
                        .foregroundStyle(LineaColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("today.goalOffer.detail")
                }
                FlowLayout(spacing: 12) {
                    LineaOutlineButton(title: offer.acceptTitle) {
                        Task { await intelligence.answerGoalOffer(offer, accepted: true) }
                    }
                    .accessibilityIdentifier("goalOffer.accept")
                    LineaOutlineButton(title: offer.declineTitle) {
                        Task { await intelligence.answerGoalOffer(offer, accepted: false) }
                    }
                    .accessibilityIdentifier("goalOffer.decline")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.goalOffer")
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
            intelligence: intelligence,
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
