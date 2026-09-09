//
//  TaskEditorView.swift
//  Linea
//
//  Create/edit a task. Presented as a native sheet but styled with the Linea
//  design system (calm fields, hairlines, ink accents) rather than a generic
//  Form. Talks to `PlanStore` intents only.
//

import SwiftUI

struct TaskEditorView: View {
    @Environment(PlanStore.self) private var plan
    @Environment(\.dismiss) private var dismiss

    /// The task being edited, or nil when creating.
    let existing: LineaTask?
    /// Default date applied to a newly created task (e.g. today).
    var defaultDate: Date?

    @State private var title: String
    @State private var isImportant: Bool
    @State private var hasDate: Bool
    @State private var date: Date
    @FocusState private var titleFocused: Bool

    init(existing: LineaTask? = nil, defaultDate: Date? = nil) {
        self.existing = existing
        self.defaultDate = defaultDate
        _title = State(initialValue: existing?.title ?? "")
        _isImportant = State(initialValue: existing?.priority.isImportant ?? false)
        let initialDate = existing?.date ?? defaultDate
        _hasDate = State(initialValue: initialDate != nil)
        _date = State(initialValue: initialDate ?? Date())
    }

    private var isEditing: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LineaMetrics.sectionSpacing) {
                    LineaTextField(placeholder: "Что нужно сделать?", text: $title, axis: .vertical)
                        .focused($titleFocused)

                    toggleRow(title: "Важно", isOn: $isImportant)

                    VStack(spacing: 0) {
                        toggleRow(title: "Дата", isOn: $hasDate.animation(.snappy))
                        if hasDate {
                            DatePicker("", selection: $date, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .tint(LineaColor.ink)
                                .labelsHidden()
                                .padding(.top, 4)
                        }
                    }

                    if isEditing {
                        Button(role: .destructive) {
                            Task {
                                if let existing { await plan.deleteTask(existing) }
                                dismiss()
                            }
                        } label: {
                            Text("Удалить задачу")
                                .font(LineaFont.control)
                                .foregroundStyle(.red)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, LineaMetrics.screenPadding)
                .padding(.vertical, 20)
            }
            .background(LineaColor.background.ignoresSafeArea())
            .navigationTitle(isEditing ? "Задача" : "Новая задача")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }.tint(LineaColor.ink)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { save() }
                        .tint(LineaColor.ink)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            if !isEditing { titleFocused = true }
        }
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            Toggle(isOn: isOn) {
                Text(title)
                    .font(LineaFont.rowTitle)
                    .foregroundStyle(LineaColor.textPrimary)
            }
            .tint(LineaColor.ink)
            .padding(.vertical, 14)
            LineaHairline()
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let result = LineaTask(
            id: existing?.id ?? UUID(),
            title: trimmedTitle,
            notes: existing?.notes,
            date: hasDate ? date : nil,
            priority: isImportant ? .important : .normal,
            isDone: existing?.isDone ?? false,
            createdAt: existing?.createdAt ?? Date()
        )
        Task {
            await plan.saveTask(result)
            dismiss()
        }
    }
}
