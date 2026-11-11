//
//  TodayView.swift
//  Linea
//
//  The day center: current action, editable queue, and one AI suggestion.

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
    @State private var movingBlock: PlanBlock?
    @State private var dismissedSuggestions: Set<String> = []

    var body: some View {
        NavigationStack {
            LineaScaffold(
                title: greeting,
                subtitle: dateSubtitle,
                headerActions: AnyView(headerActions),
                showsQuickAdd: true
            ) {
                nowSection
                timeline
                assistantCard
            }
            .sheet(item: $editingTask) { target in
                TaskEditorView(existing: target.task)
            }
            .sheet(item: $movingBlock) { block in
                QueueTimePicker(block: block)
            }
            .taskRescheduleDialog($rescheduling)
        }
        .task { await intelligence.refresh(reason: .appeared) }
        .task { await intelligence.keepNextActionFresh() }
        .onDisappear { intelligence.clearTodayNotes() }
        .refreshable { await intelligence.refresh(reason: .manual) }
        .onChange(of: intelligence.plan?.day) { dismissedSuggestions = [] }
    }

    private var headerActions: some View {
        HStack(spacing: 4) {
            headerButton("Линия AI", icon: "sparkles") { appState.openAI() }
            headerButton("Профиль", icon: "person.crop.circle") { appState.openProfile() }
        }
    }

    private func headerButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(LineaColor.textPrimary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
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
                    FlowLayout(spacing: 8) {
                        if action.isStarted {
                            LineaPrimaryButton(title: "Завершить", systemImage: "checkmark") {
                                Task { await intelligence.finishAction() }
                            }
                        } else {
                            LineaPrimaryButton(title: "Начать", systemImage: "play.fill") {
                                Task { await intelligence.startAction() }
                            }
                        }
                        nowSecondaryButton("Не сейчас") {
                            showsAlternatives = false
                            Task { await intelligence.notNowAction() }
                        }
                        // У начатого «Другое» нет: взяться за другое — «Не
                        // сейчас» или «Начать» в списке. Зато можно вернуться
                        // в фокус, если его свернули.
                        if action.isStarted, let taskID = action.taskID {
                            nowSecondaryButton("Развернуть", icon: "arrow.up.left.and.arrow.down.right") {
                                intelligence.openFocus(taskID)
                            }
                            .accessibilityIdentifier("now.openFocus")
                        } else if !action.alternatives.isEmpty {
                            nowSecondaryButton(
                                showsAlternatives ? "Скрыть" : "Другое",
                                icon: showsAlternatives ? "chevron.up" : "chevron.down"
                            ) {
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
        } else {
            // Сделал последнее — предлагать нечего, но ответ Linea виден.
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Сейчас")
                nowNote
                notNowQuestion
                if intelligence.nowNote == nil {
                    assistantText(intelligence.isRefreshing ? "Подбираю действие…" : "Пока нет действия, которое стоит начать.")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.now")
        }
    }

    private func nowSecondaryButton(
        _ title: String,
        icon: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .font(LineaFont.control)
            .foregroundStyle(LineaColor.textPrimary)
            .padding(.horizontal, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        if let confirmation = intelligence.goalOfferConfirmation, !dismissedSuggestions.contains("goal-done") {
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

    // MARK: Queue

    private var timeline: some View {
        let blocks = intelligence.visibleBlocks
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Дальше")
            if blocks.isEmpty {
                assistantText("На сегодня больше ничего не запланировано.")
            }
            VStack(spacing: 0) {
                ForEach(blocks) { block in
                    if let task = block.taskID.flatMap({ id in plan.tasks.first { $0.id == id } }) {
                        let actions = rowActions(for: task)
                        HStack(spacing: 2) {
                            PlanBlockRow(
                                block: block,
                                time: intelligence.time,
                                isDone: task.isDone,
                                onTap: { editingTask = .edit(task) }
                            )
                            .taskAccessibilityActions(actions, for: task)
                            .taskActions(actions, for: task)

                            if task.isOpen {
                                Button(action: actions.onDone) {
                                    Image(systemName: "checkmark.circle")
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Завершить: \(task.title)")
                            }

                            Menu {
                                if intelligence.canMoveInQueue(block) {
                                    queueMenu(block)
                                    Divider()
                                }
                                TaskActionsMenu(task: task, actions: actions)
                                if task.isDone {
                                    Button("Вернуть", action: actions.onDone)
                                }
                                Button("Обсудить с Линией AI", systemImage: "sparkles") {
                                    appState.openAI(prompt: "Помоги с задачей «\(task.title)» в сегодняшнем плане.")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Действия: \(task.title)")
                        }
                        .foregroundStyle(LineaColor.textSecondary)
                    } else {
                        PlanBlockRow(block: block, time: intelligence.time)
                    }
                }
            }
        }
    }

    private func queueMenu(_ block: PlanBlock) -> some View {
        Group {
            Button("Выбрать время", systemImage: "clock") { movingBlock = block }
            Button("Выше в очереди", systemImage: "arrow.up") {
                Task { await intelligence.reorderQueue(block.id, toward: .earlier) }
            }
            .disabled(intelligence.queueNeighbor(of: block, toward: .earlier) == nil)
            Button("Ниже в очереди", systemImage: "arrow.down") {
                Task { await intelligence.reorderQueue(block.id, toward: .later) }
            }
            .disabled(intelligence.queueNeighbor(of: block, toward: .later) == nil)
        }
        .disabled(intelligence.isRefreshing || intelligence.isEditingQueue)
    }

    private func rowActions(for task: LineaTask) -> TaskRowActions {
        plan.rowActions(
            for: task,
            intelligence: intelligence,
            onEdit: { editingTask = .edit(task) },
            onReschedule: { rescheduling = task }
        )
    }

    // MARK: One contextual suggestion

    private var assistantCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Линия AI")
            assistantSuggestion
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: LineaMetrics.surfaceRadius)
                .strokeBorder(LineaColor.separator, lineWidth: LineaMetrics.hairline)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.assistant")
    }

    @ViewBuilder
    private var assistantSuggestion: some View {
        if let conflict = intelligence.pinnedConflict, !dismissedSuggestions.contains(conflict.id) {
            let text = "«\(conflict.title)» пересекается с событием. Выбранное время сохранено."
            assistantText(text)
            FlowLayout(spacing: 12) {
                LineaOutlineButton(title: "Выбрать время") { movingBlock = conflict }
                dismissSuggestion(conflict.id)
            }
        } else if let nudge = intelligence.dueNudge, nudge.kind != .eveningCheckIn {
            NudgeCard(nudge: nudge) { action in
                Task { await intelligence.respond(to: nudge, action: action) }
            }
            if !nudge.actions.contains(.dismiss) {
                LineaOutlineButton(title: "Скрыть") {
                    Task { await intelligence.respond(to: nudge, action: .dismiss) }
                }
            }
        } else if intelligence.goalOffer != nil
                    || (intelligence.goalOfferConfirmation != nil && !dismissedSuggestions.contains("goal-done")) {
            goalOfferSection
            if intelligence.goalOfferConfirmation != nil { dismissSuggestion("goal-done") }
        } else if intelligence.isCheckInDue && !dismissedSuggestions.contains("evening") {
            EveningReviewCard(
                canRate: intelligence.canRateDay,
                onTell: { appState.openCheckIn() },
                onRate: { rating in Task { await intelligence.rateDay(rating) } }
            )
            dismissSuggestion("evening")
        } else if let offer = InboxReview().offer(tasks: plan.tasks, time: intelligence.time),
                  !dismissedSuggestions.contains("inbox") {
            VStack(alignment: .leading, spacing: 12) {
                assistantText(offer.text)
                FlowLayout(spacing: 12) {
                    LineaOutlineButton(title: "Разобрать") { appState.openInboxReview(.unsorted) }
                    dismissSuggestion("inbox")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.inbox")
        } else if intelligence.canAcceptPlan && !dismissedSuggestions.contains("accept") {
            assistantText("План на сегодня готов. После принятия Линия сможет напоминать о делах.")
            FlowLayout(spacing: 12) {
                LineaOutlineButton(title: "Принять план") { Task { await intelligence.acceptPlan() } }
                    .disabled(intelligence.isRefreshing || intelligence.isEditingQueue)
                discussSuggestion("Помоги оценить план на сегодня.")
                dismissSuggestion("accept")
            }
        } else if let item = intelligence.advice.first(where: { !dismissedSuggestions.contains($0.id) }) {
            assistantText(item.message)
            FlowLayout(spacing: 12) {
                ForEach(Array(item.actions.enumerated()), id: \.offset) { _, action in
                    if let title = actionTitle(action) {
                        LineaOutlineButton(title: title) {
                            if case let .openTask(id) = action,
                               let task = plan.tasks.first(where: { $0.id == id }) {
                                editingTask = .edit(task)
                            } else {
                                Task { await intelligence.perform(action) }
                            }
                        }
                    }
                }
                discussSuggestion("Расскажи подробнее об этом предложении: \(item.message)")
                dismissSuggestion(item.id)
            }
        } else {
            assistantText("Пока нет предложений по плану.")
            LineaOutlineButton(title: "Открыть чат") { appState.openAI() }
        }
    }

    private func assistantText(_ text: String) -> some View {
        Text(text)
            .font(LineaFont.rowTitle)
            .foregroundStyle(LineaColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func discussSuggestion(_ prompt: String) -> some View {
        LineaOutlineButton(title: "Обсудить") { appState.openAI(prompt: prompt) }
    }

    private func dismissSuggestion(_ id: String) -> some View {
        LineaOutlineButton(title: "Скрыть") { _ = dismissedSuggestions.insert(id) }
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

private struct QueueTimePicker: View {
    @Environment(IntelligenceStore.self) private var intelligence
    @Environment(\.dismiss) private var dismiss
    let block: PlanBlock
    @State private var selection: Date
    @State private var error: String?
    @State private var saving = false

    init(block: PlanBlock) {
        self.block = block
        _selection = State(initialValue: max(block.start, .now.addingTimeInterval(60)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Text(block.title)
                DatePicker("Начало", selection: $selection, displayedComponents: .hourAndMinute)
                    .environment(\.timeZone, intelligence.time.timeZone)
                Text("Длительность: \(block.durationMinutes) мин")
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle("Выбрать время")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        Task {
                            saving = true
                            error = await intelligence.moveInQueue(block.id, to: selection)
                            saving = false
                            if error == nil { dismiss() }
                        }
                    }
                    .disabled(saving || intelligence.isRefreshing)
                }
            }
            .interactiveDismissDisabled(saving)
        }
    }
}
