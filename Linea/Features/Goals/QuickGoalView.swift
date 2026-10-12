//
//  QuickGoalView.swift
//  Linea
//
//  Новая цель за пару секунд, как новая задача (ADR-035). Не форма, а один
//  вопрос — «Чего хочешь достичь?». Строка «Выпустить Линия в TestFlight до
//  15-го октября» сразу видна такой, какой станет целью: «Выпустить Линия в
//  TestFlight», «до 15 октября». Под ней — чипы самого важного, как у задачи:
//  срок, важность, как считать прогресс, чья цель. Серый чип — решила Linea,
//  чёрный — сказано или выбрано. У цели команды или компании — «За какую
//  часть отвечаешь ты?» текстом или голосом (ADR-038). «Создать цель» — и
//  всё; «Рассказать подробнее» — что уже есть и как поймём, что получилось.
//
//  Экран только показывает `GoalIntakeStore`; что получится из строки,
//  решает ядро (`QuickGoalDraft`).
//

import SwiftUI

struct QuickGoalView: View {
    @Environment(GoalIntakeStore.self) private var store
    var onClose: () -> Void
    var onCreated: () -> Void
    /// Высота содержимого — по ней лист выбирает свою высоту.
    var onHeight: (CGFloat) -> Void

    @FocusState private var isFocused: Bool
    @State private var isPickingDeadline = false

    var body: some View {
        @Bindable var store = store
        let resolution = store.resolution

        VStack(alignment: .leading, spacing: 16) {
            header
            line(text: $store.draft.text)
            understood(resolution)
            chips(resolution)
            ownPart(resolution)
            status
            actions
        }
        .padding(.horizontal, LineaMetrics.screenPadding)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            onHeight(height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { isFocused = true }
    }

    // MARK: Шапка

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LineaColor.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(LineaColor.fill))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Закрыть")
            Spacer()
            Text("Новая цель")
                .font(LineaFont.control)
                .foregroundStyle(LineaColor.textPrimary)
            Spacer()
            // Кнопка создания — внизу, «Создать цель»; справа — пусто, для равновесия.
            Color.clear.frame(width: 40, height: 40)
        }
    }

    // MARK: Строка

    private func line(text: Binding<String>) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                TextField("Чего хочешь достичь?", text: text, axis: .vertical)
                    .font(LineaFont.feature)
                    .foregroundStyle(LineaColor.textPrimary)
                    .tint(LineaColor.ink)
                    .lineLimit(1...3)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .accessibilityIdentifier("goal.line")
                    .onChange(of: text.wrappedValue) { _, value in
                        // В многострочном поле «Готово» вставляет перевод строки — это «Создать цель».
                        guard value.contains("\n") else { return }
                        text.wrappedValue = value
                            .replacingOccurrences(of: "\n", with: " ")
                            .trimmingCharacters(in: .whitespaces)
                        create()
                    }
                micButton
            }
            LineaHairline()
        }
    }

    private var micButton: some View {
        let phase = store.dictationTarget == .line ? store.dictation.phase : .idle
        return Button {
            store.toggleDictation(for: .line)
        } label: {
            Group {
                switch phase {
                case .idle:
                    Image(systemName: "mic")
                        .foregroundStyle(LineaColor.textSecondary)
                case .recording:
                    Image(systemName: "stop.fill")
                        .foregroundStyle(LineaColor.onInk)
                case .transcribing:
                    ProgressView()
                        .tint(LineaColor.textSecondary)
                }
            }
            .font(.body.weight(.medium))
            .frame(width: 40, height: 40)
            .background(Circle().fill(phase == .recording ? LineaColor.ink : LineaColor.fill))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(store.dictation.phase == .transcribing || (store.dictation.phase != .idle && store.dictationTarget != .line))
        .accessibilityLabel(phase == .recording ? "Закончить запись" : "Надиктовать цель")
    }

    // MARK: Как Linea поняла

    /// Цель так, как она сохранится: название без срока и важности и строка
    /// «до 15 октября · Высокая» — только сказанное и выбранное.
    @ViewBuilder
    private func understood(_ resolution: QuickGoalResolution) -> some View {
        if resolution.isUnderstood, resolution.canCreate {
            let summary = QuickGoalText.summary(resolution, time: store.time)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LineaColor.textTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(resolution.title)
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textPrimary)
                        .lineLimit(2)
                        .accessibilityIdentifier("goal.understood.title")
                    if !summary.isEmpty {
                        Text(summary)
                            .font(LineaFont.caption)
                            .foregroundStyle(LineaColor.textSecondary)
                            .accessibilityIdentifier("goal.understood.summary")
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("goal.understood")
        }
    }

    // MARK: Чипы

    /// Срок, важность, прогресс, чья цель — не больше четырёх, как у задачи.
    /// Не влезли в ширину — переносятся на вторую строку.
    private func chips(_ resolution: QuickGoalResolution) -> some View {
        FlowLayout(spacing: 8) {
            deadlineChip(resolution)
            priorityChip(resolution)
            methodChip(resolution)
            scopeChip(resolution)
        }
    }

    private func deadlineChip(_ resolution: QuickGoalResolution) -> some View {
        let time = store.time
        let title = QuickGoalText.deadlineChip(resolution, time: time)
        let chosen = resolution.understanding.deadline
        return Menu {
            ForEach(GoalDeadlineOption.allCases, id: \.self) { option in
                let date = option.date(time: time)
                Button { store.chooseDeadline(date) } label: {
                    choice(QuickGoalText.deadlineOption(option, time: time),
                           isSelected: chosen.map { time.isSameDay($0, date) } ?? false)
                }
            }
            Button { openDeadlinePicker() } label: { Label("Выбрать дату…", systemImage: "calendar") }
            Divider()
            Button { store.chooseDeadline(nil) } label: {
                choice("Без срока", isSelected: chosen == nil && resolution.deadlineOrigin == .chosen)
            }
        } label: {
            TaskChip(systemImage: "calendar", title: title, isMuted: resolution.deadlineOrigin == .assumed)
        }
        .accessibilityLabel("Срок: \(title)")
        .popover(isPresented: $isPickingDeadline, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            deadlinePicker(resolution)
        }
    }

    private func priorityChip(_ resolution: QuickGoalResolution) -> some View {
        let priority = resolution.understanding.priority
        let title = LineaGoal.importanceTitle(priority)
        return Menu {
            ForEach(TaskPriority.allCases, id: \.self) { option in
                Button { store.choosePriority(option) } label: {
                    choice(LineaGoal.importanceTitle(option), isSelected: priority == option)
                }
            }
        } label: {
            TaskChip(systemImage: priority == .important ? "flag.fill" : "flag", title: title,
                     isMuted: resolution.priorityOrigin == .assumed)
        }
        .accessibilityLabel("Важность: \(title)")
    }

    /// Как считать прогресс: Linea выбрала по типу цели, человек меняет.
    private func methodChip(_ resolution: QuickGoalResolution) -> some View {
        let method = resolution.understanding.method
        let title = QuickGoalText.methodChip(resolution)
        return Menu {
            ForEach(GoalProgressMethod.allCases, id: \.self) { option in
                Button { store.chooseMethod(option) } label: {
                    choice(option.title, isSelected: method == option)
                }
            }
        } label: {
            TaskChip(systemImage: "chart.bar", title: title, isMuted: resolution.methodOrigin == .assumed)
                .frame(maxWidth: 230)
        }
        .accessibilityLabel("Прогресс: \(title)")
    }

    /// Чья цель: «От меня», «От команды», «От компании». Команду и компанию
    /// Linea видит в словах («выручку компании») — чип чёрный.
    private func scopeChip(_ resolution: QuickGoalResolution) -> some View {
        let scope = resolution.understanding.scope
        return Menu {
            ForEach(GoalScope.allCases, id: \.self) { option in
                Button { store.chooseScope(option) } label: {
                    choice(option.choiceTitle, isSelected: scope == option)
                }
            }
        } label: {
            TaskChip(systemImage: Self.icon(for: scope), title: scope.choiceTitle,
                     isMuted: resolution.scopeOrigin == .assumed)
        }
        .accessibilityLabel("Чья цель: \(scope.choiceTitle)")
    }

    static func icon(for scope: GoalScope) -> String {
        switch scope {
        case .personal: return "person"
        case .team: return "person.2"
        case .company: return "building.2"
        }
    }

    // MARK: Своя часть

    /// У цели команды или компании — за какую часть отвечает сам человек:
    /// шаги и окна Linea будет предлагать только в ней.
    @ViewBuilder
    private func ownPart(_ resolution: QuickGoalResolution) -> some View {
        @Bindable var store = store
        let phase = store.dictationTarget == .part ? store.dictation.phase : .idle
        if resolution.understanding.scope.isShared {
            VStack(alignment: .leading, spacing: 8) {
                Text("За какую часть отвечаешь ты?")
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textSecondary)
                TextField("Я отвечаю за продажи крупным клиентам…", text: $store.draft.ownerScope, axis: .vertical)
                    .font(LineaFont.rowTitle)
                    .foregroundStyle(LineaColor.textPrimary)
                    .tint(LineaColor.ink)
                    .lineLimit(1...3)
                    .accessibilityIdentifier("goal.part")
                LineaHairline()
                Button {
                    isFocused = false
                    store.toggleDictation(for: .part)
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
                .disabled(store.dictation.phase == .transcribing || (store.dictation.phase != .idle && store.dictationTarget != .part))
                .accessibilityIdentifier("goal.part.voice")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("goal.ownPart")
        }
    }

    @ViewBuilder
    private func choice(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    // MARK: Срок — календарь

    /// Календарь: тап по дню выбирает срок и закрывает выбор.
    private func deadlinePicker(_ resolution: QuickGoalResolution) -> some View {
        let time = store.time
        return DatePicker(
            "Срок",
            selection: Binding(
                get: { resolution.understanding.deadline ?? time.adding(days: 30, to: time.today) },
                set: { picked in
                    store.chooseDeadline(time.startOfDay(picked))
                    isPickingDeadline = false
                }
            ),
            in: time.today...,
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
        .tint(LineaColor.ink)
        .padding(12)
        .frame(width: 330)
        .presentationCompactAdaptation(.popover)
    }

    /// Календарь открывается без клавиатуры: с ней ему не хватает места, и
    /// iOS ставит его за край экрана (как у быстрой задачи).
    private func openDeadlinePicker() {
        guard isFocused else {
            isPickingDeadline = true
            return
        }
        isFocused = false
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            isPickingDeadline = true
        }
    }

    // MARK: Голос

    @ViewBuilder
    private var status: some View {
        switch store.dictation.phase {
        case .recording:
            caption("Слушаю · \(clock(store.dictation.recorder.elapsed)). Можно целиком: «выпустить приложение до 15 октября».")
        case .transcribing:
            caption("Распознаю на телефоне…")
        case .idle:
            if let notice = store.dictation.notice {
                caption(notice)
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(LineaFont.caption)
            .foregroundStyle(LineaColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: Кнопки

    private var actions: some View {
        VStack(spacing: 4) {
            LineaPrimaryButton(title: "Создать цель", fillsWidth: true) { create() }
                .disabled(!store.canCreateQuick)
                .accessibilityIdentifier("goal.create")
            Button("Рассказать подробнее") {
                isFocused = false
                store.tellMore()
            }
            .font(LineaFont.control)
            .tint(LineaColor.textSecondary)
            .padding(.vertical, 8)
            .disabled(!store.canCreateQuick)
            .accessibilityIdentifier("goal.more")
        }
        .padding(.top, 4)
    }

    private func create() {
        Task {
            if await store.createQuick() { onCreated() }
        }
    }
}
