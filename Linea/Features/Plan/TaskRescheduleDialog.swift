//
//  TaskRescheduleDialog.swift
//  Linea
//
//  «Перенести» — свайп влево по задаче. Снизу выезжает короткий выбор:
//  «Сегодня», «Завтра», «На неделе · до вс, 4 окт», «На следующей неделе ·
//  пн, 5 окт», «Выбрать дату…», «Без даты» — кроме того, где задача уже
//  стоит. «Выбрать дату…» открывает календарь: тап по дню переносит сразу.
//  Варианты и то, что станет с задачей, — из ядра (`TaskReschedule`).
//
//  Здесь же — обработчики строки задачи для «Плана» и «Сегодня»
//  (`PlanStore.rowActions`), чтобы оба экрана вели себя одинаково.
//

import SwiftUI

extension View {
    /// Выбор «Перенести» для задачи из `task`; закрылся — `task` снова `nil`.
    func taskRescheduleDialog(_ task: Binding<LineaTask?>) -> some View {
        modifier(TaskRescheduleDialog(task: task))
    }
}

private struct TaskRescheduleDialog: ViewModifier {
    @Binding var task: LineaTask?

    @Environment(PlanStore.self) private var plan
    @Environment(UserProfileStore.self) private var profile
    @Environment(IntelligenceStore.self) private var intelligence
    @State private var pickingDay: LineaTask?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                task.map { "Перенести «\($0.title)»" } ?? "Перенести",
                isPresented: Binding(get: { task != nil }, set: { if !$0 { task = nil } }),
                titleVisibility: .visible,
                presenting: task
            ) { task in
                ForEach(TaskReschedule().options(for: task, profile: profile.profile, time: intelligence.time)) { option in
                    Button(option.title) { move(task, to: option.target) }
                }
                Button("Выбрать дату…") { pickingDay = task }
                Button("Отмена", role: .cancel) {}
            }
            .sheet(item: $pickingDay) { task in
                RescheduleDaySheet(task: task, time: intelligence.time) { day in
                    move(task, to: .day(day))
                }
            }
    }

    private func move(_ task: LineaTask, to target: TaskReschedule.Target) {
        Task { await plan.rescheduleTask(task, to: target, profile: profile.profile) }
    }
}

/// Свой день для «Перенести»: календарь, тап по дню — и готово.
private struct RescheduleDaySheet: View {
    let task: LineaTask
    let time: TimeContext
    let onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var day: Date

    init(task: LineaTask, time: TimeContext, onPick: @escaping (Date) -> Void) {
        self.task = task
        self.time = time
        self.onPick = onPick
        // Будущий день задачи — он и выбран; иначе — завтра.
        let tomorrow = time.adding(days: 1, to: time.today)
        let current = task.date.map(time.startOfDay)
        _day = State(initialValue: current.map { $0 > time.today ? $0 : tomorrow } ?? tomorrow)
    }

    var body: some View {
        NavigationStack {
            DatePicker("День", selection: $day, in: time.today..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(LineaColor.ink)
                .padding(.horizontal, LineaMetrics.screenPadding)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(LineaColor.background.ignoresSafeArea())
                .navigationTitle("Перенести")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { dismiss() }.tint(LineaColor.ink)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") { pick(day) }.tint(LineaColor.ink)
                    }
                }
                // Как в быстром вводе: тап по дню выбирает его сразу.
                .onChange(of: day) { _, newDay in pick(newDay) }
        }
        .presentationDetents([.fraction(0.66), .large])
        .presentationDragIndicator(.visible)
    }

    private func pick(_ day: Date) {
        onPick(day)
        dismiss()
    }
}

extension PlanStore {
    /// Обработчики строки задачи: закрыть, перенести, изменить, цель,
    /// приоритет, удалить. «Изменить» и «Перенести» открывает экран.
    func rowActions(
        for task: LineaTask,
        onEdit: @escaping () -> Void,
        onReschedule: @escaping () -> Void
    ) -> TaskRowActions {
        TaskRowActions(
            goals: goals.filter { ($0.isActive && !$0.isCompleted) || $0.id == task.goalID },
            onDone: { Task { await self.toggleTask(task) } },
            onReschedule: onReschedule,
            onEdit: onEdit,
            onLinkGoal: { goalID in Task { await self.linkTask(task, toGoal: goalID) } },
            onPriority: { priority in Task { await self.setPriority(priority, of: task) } },
            onDelete: { Task { await self.deleteTask(task) } }
        )
    }
}
