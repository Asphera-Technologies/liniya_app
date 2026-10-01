//
//  QuickAddView.swift
//  Linea
//
//  Новая задача за пару секунд: название и «Добавить». Под строкой — чипы
//  параметров. Что Linea поняла из сказанного («завтра», «на полчаса»,
//  «важно»), там уже стоит; чего не поняла — стоит значение по умолчанию,
//  серым. Любой чип меняется одним нажатием, всё остальное — потом, в
//  карточке задачи. Микрофон в строке — надиктовать задачу целиком.
//
//  Экран только показывает `QuickAddStore`; что получится из ввода, решает
//  ядро (`QuickTaskDraft`).
//

import SwiftUI

struct QuickAddView: View {
    @Environment(QuickAddStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTitleFocused: Bool
    /// Строка со сроком под чипами: открывается из чипа «Когда».
    @State private var isEditingDeadline = false

    private static let durations = [15, 30, 45, 60, 90, 120]

    var body: some View {
        @Bindable var store = store
        let resolution = store.resolution

        VStack(alignment: .leading, spacing: 16) {
            header(canSave: resolution.canSave)
            titleField(text: $store.draft.text)
            chips(resolution)
            if isEditingDeadline {
                deadlineRow(resolution)
            }
            status
        }
        .padding(.horizontal, LineaMetrics.screenPadding)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LineaColor.background.ignoresSafeArea())
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

    // MARK: Чипы

    private func chips(_ resolution: QuickTaskResolution) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                dayChip(resolution)
                durationChip(resolution)
                priorityChip(resolution)
                if !store.activeGoals.isEmpty {
                    goalChip(resolution)
                }
            }
        }
    }

    private func dayChip(_ resolution: QuickTaskResolution) -> some View {
        let title = QuickTaskText.day(resolution, time: store.time)
        return Menu {
            Button { store.chooseDay(.today) } label: { option("Сегодня", isSelected: resolution.day == .today) }
            Button { store.chooseDay(.tomorrow) } label: { option("Завтра", isSelected: resolution.day == .tomorrow) }
            Button { startDeadline(resolution) } label: { Label("Срок…", systemImage: "flag.checkered") }
            Button { store.chooseDay(.someday) } label: { option("Без даты", isSelected: resolution.date == nil && resolution.deadline == nil) }
        } label: {
            TaskChip(systemImage: "calendar", title: title,
                     isMuted: resolution.dayOrigin == .assumed && resolution.deadlineOrigin == .assumed)
        }
        .accessibilityLabel("Когда: \(title)")
    }

    private func durationChip(_ resolution: QuickTaskResolution) -> some View {
        let minutes = resolution.minutes ?? LineaTask.defaultEstimatedMinutes
        let title = QuickTaskText.duration(minutes: minutes)
        return Menu {
            ForEach(Self.durations, id: \.self) { value in
                Button { store.chooseMinutes(value) } label: {
                    option(RussianText.duration(minutes: value), isSelected: resolution.minutes == value)
                }
            }
        } label: {
            TaskChip(systemImage: "clock", title: title, isMuted: resolution.minutes == nil)
        }
        .accessibilityLabel("Сколько займёт: \(title)")
    }

    private func priorityChip(_ resolution: QuickTaskResolution) -> some View {
        Menu {
            ForEach(TaskPriority.allCases, id: \.self) { priority in
                Button { store.choosePriority(priority) } label: {
                    option(priority.title, isSelected: resolution.priority == priority)
                }
            }
        } label: {
            TaskChip(systemImage: "flag", title: resolution.priority.title,
                     isMuted: resolution.priorityOrigin == .assumed)
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
                    Label("Похоже, к цели «\(suggested.title)»", systemImage: "sparkles")
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

    // MARK: Срок

    private func startDeadline(_ resolution: QuickTaskResolution) {
        if resolution.deadline == nil {
            store.chooseDeadline(defaultDeadline(for: resolution))
        }
        withAnimation(.snappy) { isEditingDeadline = true }
    }

    /// Срок по умолчанию — 18:00 дня задачи, а если уже поздно — завтра.
    private func defaultDeadline(for resolution: QuickTaskResolution) -> Date {
        let time = store.time
        let evening = TimeOfDay(hour: 18)
        let moment = time.date(on: resolution.date ?? time.today, at: evening)
        return moment > time.now ? moment : time.date(on: time.adding(days: 1, to: time.today), at: evening)
    }

    private func deadlineRow(_ resolution: QuickTaskResolution) -> some View {
        HStack(spacing: 12) {
            Text("Срок")
                .font(LineaFont.rowTitle)
                .foregroundStyle(LineaColor.textSecondary)
            DatePicker(
                "Срок",
                selection: Binding(
                    get: { resolution.deadline ?? defaultDeadline(for: resolution) },
                    set: { store.chooseDeadline($0) }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(LineaColor.ink)
            Spacer(minLength: 0)
            Button {
                store.chooseDeadline(nil)
                withAnimation(.snappy) { isEditingDeadline = false }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(LineaColor.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Без срока")
        }
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
