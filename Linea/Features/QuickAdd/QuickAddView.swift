//
//  QuickAddView.swift
//  Linea
//
//  Новая задача за пару секунд: название и «Добавить». Полной формы при
//  создании нет — под строкой только самое важное, компактными чипами:
//  «Сегодня  ~30 мин  Средний», и цель, если цели есть. Не больше четырёх
//  чипов одновременно. Что Linea поняла из сказанного («завтра», «на
//  полчаса», «важно»), там уже стоит; чего не поняла — значение по умолчанию,
//  серым. Тап по чипу — маленький выбор; остальное меняется потом, в карточке
//  задачи. Микрофон в строке — надиктовать задачу целиком.
//
//  Экран только показывает `QuickAddStore`; что получится из ввода, решает
//  ядро (`QuickTaskDraft`). Когда Linea что-то поняла из слов, под строкой
//  видно задачу такой, какой она сохранится: «Подготовить КП для клиента» и
//  «Завтра · до 12:00 · ~1 ч 30 мин · Высокий» — только сказанное и выбранное.
//

import SwiftUI

struct QuickAddView: View {
    @Environment(QuickAddStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTitleFocused: Bool
    /// Маленький выбор поверх чипа «Когда»: календарь дня или срок.
    @State private var dayPopover: DayPopover?
    /// Колесо «Другое…» у чипа длительности.
    @State private var isPickingMinutes = false
    /// Высота листа — по содержимому: строка, чипы, пояснение.
    @State private var contentHeight: CGFloat = 200

    private enum DayPopover: String, Identifiable {
        case day, deadline
        var id: String { rawValue }
    }

    /// Варианты из чипа длительности; остальное — «Другое…».
    private static let durations = [15, 30, 45, 60]
    /// Колесо «Другое…»: от пяти минут до рабочего дня.
    private static let customDurations = [5, 10, 15, 20, 25, 30, 40, 45, 50, 60, 75, 90, 105, 120, 150, 180, 210, 240, 300, 360, 420, 480]

    var body: some View {
        @Bindable var store = store
        let resolution = store.resolution

        VStack(alignment: .leading, spacing: 16) {
            header(canSave: resolution.canSave)
            titleField(text: $store.draft.text)
            understood(resolution)
            chips(resolution)
            status
        }
        .padding(.horizontal, LineaMetrics.screenPadding)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            contentHeight = height
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LineaColor.background.ignoresSafeArea())
        // Невысокий лист над клавиатурой — ровно по содержимому.
        .presentationDetents([.height(max(contentHeight, 160))])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(store.voice != .idle)
        .onAppear { isTitleFocused = true }
    }

    // MARK: Шапка

    private func header(canSave: Bool) -> some View {
        HStack {
            circleButton(systemImage: "xmark", isProminent: false) { dismiss() }
                .accessibilityLabel("Закрыть")
            Spacer()
            Text("Новая задача")
                .font(LineaFont.control)
                .foregroundStyle(LineaColor.textPrimary)
            Spacer()
            circleButton(systemImage: "checkmark", isProminent: canSave) { save() }
                .disabled(!canSave || store.isSaving)
                .accessibilityLabel("Добавить задачу")
        }
    }

    private func circleButton(systemImage: String, isProminent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(isProminent ? LineaColor.onInk : LineaColor.textSecondary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(isProminent ? LineaColor.ink : LineaColor.fill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Строка

    private func titleField(text: Binding<String>) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                TextField("Что нужно сделать?", text: text, axis: .vertical)
                    .font(LineaFont.feature)
                    .foregroundStyle(LineaColor.textPrimary)
                    .tint(LineaColor.ink)
                    .lineLimit(1...3)
                    .focused($isTitleFocused)
                    .submitLabel(.done)
                    .accessibilityIdentifier("quickAdd.title")
                    .onChange(of: text.wrappedValue) { _, value in
                        // В многострочном поле «Готово» вставляет перевод строки — это «Добавить».
                        guard value.contains("\n") else { return }
                        text.wrappedValue = value
                            .replacingOccurrences(of: "\n", with: " ")
                            .trimmingCharacters(in: .whitespaces)
                        save()
                    }
                micButton
            }
            LineaHairline()
        }
    }

    private var micButton: some View {
        Button {
            store.toggleVoice()
        } label: {
            Group {
                switch store.voice {
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
            .background(Circle().fill(store.voice == .recording ? LineaColor.ink : LineaColor.fill))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(store.voice == .transcribing)
        .accessibilityLabel(store.voice == .recording ? "Закончить запись" : "Надиктовать задачу")
    }

    // MARK: Как Linea поняла

    /// Задача так, как она сохранится: название без распознанного и строка
    /// параметров. Только то, что сказано или выбрано: чего Linea не поняла,
    /// того здесь нет — значения по умолчанию остаются серыми в чипах.
    @ViewBuilder
    private func understood(_ resolution: QuickTaskResolution) -> some View {
        if resolution.isUnderstood, resolution.canSave {
            let summary = QuickTaskText.summary(resolution, time: store.time)
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
                        .accessibilityIdentifier("quickAdd.understood.title")
                    if !summary.isEmpty {
                        Text(summary)
                            .font(LineaFont.caption)
                            .foregroundStyle(LineaColor.textSecondary)
                            .accessibilityIdentifier("quickAdd.understood.summary")
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("quickAdd.understood")
        }
    }

    // MARK: Чипы

    /// Когда, сколько, приоритет — всегда; цель — четвёртым, если цели есть.
    /// Не влезли в ширину — переносятся на вторую строку, а не прячутся за край.
    private func chips(_ resolution: QuickTaskResolution) -> some View {
        FlowLayout(spacing: 8) {
            dayChip(resolution)
            durationChip(resolution)
            priorityChip(resolution)
            if !store.activeGoals.isEmpty {
                goalChip(resolution)
            }
        }
    }

    private func dayChip(_ resolution: QuickTaskResolution) -> some View {
        let title = QuickTaskText.day(resolution, time: store.time)
        return Menu {
            Button { store.chooseDay(.today) } label: { option("Сегодня", isSelected: resolution.day == .today) }
            Button { store.chooseDay(.tomorrow) } label: { option("Завтра", isSelected: resolution.day == .tomorrow) }
            Button { store.chooseDay(.thisWeek) } label: { option("На неделе", isSelected: resolution.day == .thisWeek) }
            Button { openPopover { dayPopover = .day } } label: { Label("Выбрать дату…", systemImage: "calendar") }
            Divider()
            Button { startDeadline(resolution) } label: { Label("Срок…", systemImage: "flag.checkered") }
            Button { clearDay() } label: { option("Без даты", isSelected: resolution.date == nil && resolution.deadline == nil) }
        } label: {
            TaskChip(systemImage: "calendar", title: title,
                     isMuted: resolution.dayOrigin == .assumed && resolution.deadlineOrigin == .assumed)
        }
        .accessibilityLabel("Когда: \(title)")
        .popover(item: $dayPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) { popover in
            switch popover {
            case .day: dayPicker(resolution)
            case .deadline: deadlinePicker(resolution)
            }
        }
    }

    private func durationChip(_ resolution: QuickTaskResolution) -> some View {
        let minutes = resolution.estimatedMinutes
        let title = QuickTaskText.duration(minutes: minutes)
        return Menu {
            ForEach(Self.durations, id: \.self) { value in
                Button { store.chooseMinutes(value) } label: {
                    option(value == 60 ? "1 час" : RussianText.duration(minutes: value), isSelected: resolution.minutes == value)
                }
            }
            Button { startCustomMinutes(resolution) } label: {
                let custom = resolution.minutes.map { !Self.durations.contains($0) } ?? false
                option(custom ? "Другое: \(RussianText.duration(minutes: minutes))" : "Другое…", isSelected: custom)
            }
        } label: {
            TaskChip(systemImage: "clock", title: title, isMuted: resolution.minutes == nil)
        }
        .accessibilityLabel("Сколько займёт: \(title)")
        .popover(isPresented: $isPickingMinutes, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            minutesPicker(resolution)
        }
    }

    private func priorityChip(_ resolution: QuickTaskResolution) -> some View {
        Menu {
            ForEach(TaskPriority.allCases, id: \.self) { priority in
                Button { store.choosePriority(priority) } label: {
                    option(priority.title, isSelected: resolution.priority == priority)
                }
            }
        } label: {
            TaskChip(systemImage: resolution.priority == .important ? "flag.fill" : "flag",
                     title: resolution.priority.title, isMuted: resolution.priorityOrigin == .assumed)
        }
        .accessibilityLabel("Приоритет: \(resolution.priority.title)")
    }

    private func goalChip(_ resolution: QuickTaskResolution) -> some View {
        let linked = store.goal(with: resolution.goalID)
        let suggested = store.goal(with: resolution.suggestion?.goalID)
        let title = linked?.title ?? suggested.map { "\($0.title)?" } ?? "Цель"
        return Menu {
            if let suggested {
                Button { store.chooseGoal(suggested.id) } label: {
                    Label("Связать с целью «\(suggested.title)»", systemImage: "sparkles")
                }
                Divider()
            }
            ForEach(store.activeGoals) { goal in
                Button { store.chooseGoal(goal.id) } label: {
                    option(goal.title, isSelected: resolution.goalID == goal.id)
                }
            }
            Divider()
            Button { store.chooseGoal(nil) } label: {
                option("Без цели", isSelected: resolution.goalID == nil && resolution.goalOrigin == .chosen)
            }
        } label: {
            TaskChip(systemImage: suggested != nil ? "sparkles" : "scope", title: title, isMuted: linked == nil)
                .frame(maxWidth: 200)
        }
        .accessibilityLabel(linked.map { "Цель: \($0.title)" } ?? suggested.map { "Похоже, к цели «\($0.title)»" } ?? "Цель не выбрана")
    }

    @ViewBuilder
    private func option(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    // MARK: Маленькие выборы

    /// Календарь: тап по дню выбирает его и закрывает выбор.
    private func dayPicker(_ resolution: QuickTaskResolution) -> some View {
        let time = store.time
        return DatePicker(
            "День",
            selection: Binding(
                get: { resolution.date ?? time.today },
                set: { picked in
                    store.chooseDay(.date(time.startOfDay(picked)))
                    dayPopover = nil
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

    private func deadlinePicker(_ resolution: QuickTaskResolution) -> some View {
        let time = store.time
        return VStack(spacing: 8) {
            DatePicker(
                "Срок",
                selection: Binding(
                    get: { resolution.deadline ?? defaultDeadline(for: resolution) },
                    set: { store.chooseDeadline($0) }
                ),
                in: time.now...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(LineaColor.ink)
            HStack {
                Button("Без срока") {
                    store.chooseDeadline(nil)
                    dayPopover = nil
                }
                .tint(LineaColor.textSecondary)
                Spacer()
                Button("Готово") { dayPopover = nil }
                    .font(LineaFont.control)
                    .tint(LineaColor.ink)
                    .accessibilityIdentifier("quickAdd.deadline.done")
            }
        }
        .padding(12)
        .frame(width: 330)
        .presentationCompactAdaptation(.popover)
    }

    private func minutesPicker(_ resolution: QuickTaskResolution) -> some View {
        VStack(spacing: 4) {
            Picker(
                "Сколько займёт",
                selection: Binding(
                    get: { Self.nearestCustom(resolution.estimatedMinutes) },
                    set: { store.chooseMinutes($0) }
                )
            ) {
                ForEach(Self.customDurations, id: \.self) { value in
                    Text(RussianText.duration(minutes: value)).tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 150)
            Button("Готово") { isPickingMinutes = false }
                .font(LineaFont.control)
                .tint(LineaColor.ink)
                .accessibilityIdentifier("quickAdd.minutes.done")
        }
        .padding(12)
        .frame(width: 240)
        .presentationCompactAdaptation(.popover)
    }

    private static func nearestCustom(_ minutes: Int) -> Int {
        customDurations.min { abs($0 - minutes) < abs($1 - minutes) } ?? minutes
    }

    private func startCustomMinutes(_ resolution: QuickTaskResolution) {
        // На колесе сразу стоит текущая оценка — «Готово» без прокрутки её и оставит.
        store.chooseMinutes(Self.nearestCustom(resolution.estimatedMinutes))
        openPopover { isPickingMinutes = true }
    }

    private func startDeadline(_ resolution: QuickTaskResolution) {
        if resolution.deadline == nil {
            store.chooseDeadline(defaultDeadline(for: resolution))
        }
        openPopover { dayPopover = .deadline }
    }

    /// Маленький выбор открывается без клавиатуры: с ней календарю не хватает
    /// места, и iOS ставит его сбоку от чипа — за край экрана. Клавиатура
    /// уходит, лист опускается, и выбор встаёт над чипом.
    private func openPopover(_ show: @escaping () -> Void) {
        guard isTitleFocused else {
            show()
            return
        }
        isTitleFocused = false
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            show()
        }
    }

    /// «Без даты»: ни дня, ни срока.
    private func clearDay() {
        store.chooseDay(.someday)
        store.chooseDeadline(nil)
    }

    /// Срок по умолчанию — 18:00 дня задачи, а если уже поздно — завтра.
    private func defaultDeadline(for resolution: QuickTaskResolution) -> Date {
        let time = store.time
        let evening = TimeOfDay(hour: 18)
        let moment = time.date(on: resolution.date ?? time.today, at: evening)
        return moment > time.now ? moment : time.date(on: time.adding(days: 1, to: time.today), at: evening)
    }

    // MARK: Состояние

    @ViewBuilder
    private var status: some View {
        switch store.voice {
        case .recording:
            caption("Слушаю · \(clock(store.recorder.elapsed)). Можно целиком: «завтра в 10, на час, важно».")
        case .transcribing:
            caption("Распознаю на телефоне…")
        case .idle:
            if let notice = store.notice {
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

    // MARK: Действия

    private func save() {
        Task {
            if await store.save() { dismiss() }
        }
    }
}
