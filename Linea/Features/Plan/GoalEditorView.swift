//
//  GoalEditorView.swift
//  Linea
//
//  Create/edit a goal, including updating progress and marking complete.
//  Native sheet, Linea-styled. Talks to `PlanStore` intents only.
//

import SwiftUI

struct GoalEditorView: View {
    @Environment(PlanStore.self) private var plan
    @Environment(\.dismiss) private var dismiss

    let existing: LineaGoal?

    @State private var title: String
    @State private var progress: Double
    @State private var isCompleted: Bool
    @FocusState private var titleFocused: Bool

    init(existing: LineaGoal? = nil) {
        self.existing = existing
        _title = State(initialValue: existing?.title ?? "")
        _progress = State(initialValue: existing?.progress ?? 0)
        _isCompleted = State(initialValue: existing?.isCompleted ?? false)
    }

    private var isEditing: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LineaMetrics.sectionSpacing) {
                    LineaTextField(placeholder: "Название цели", text: $title, axis: .vertical)
                        .focused($titleFocused)

                    progressSection

                    VStack(spacing: 0) {
                        Toggle(isOn: $isCompleted.animation(.snappy)) {
                            Text("Выполнено")
                                .font(LineaFont.rowTitle)
                                .foregroundStyle(LineaColor.textPrimary)
                        }
                        .tint(LineaColor.ink)
                        .padding(.vertical, 14)
                        LineaHairline()
                    }

                    if isEditing {
                        Button(role: .destructive) {
                            Task {
                                if let existing { await plan.deleteGoal(existing) }
                                dismiss()
                            }
                        } label: {
                            Text("Удалить цель")
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
            .navigationTitle(isEditing ? "Цель" : "Новая цель")
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

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Прогресс")
                    .font(LineaFont.sectionLabel)
                    .foregroundStyle(LineaColor.textSecondary)
                Spacer()
                Text("\(Int((displayProgress * 100).rounded()))%")
                    .font(LineaFont.sectionLabel)
                    .foregroundStyle(LineaColor.textTertiary)
                    .monospacedDigit()
            }
            DashProgress(progress: displayProgress)
            Slider(value: $progress, in: 0...1, step: 0.05) {
                Text("Прогресс")
            }
            .tint(LineaColor.ink)
            .disabled(isCompleted)
            .opacity(isCompleted ? 0.4 : 1)
        }
    }

    private var displayProgress: Double {
        isCompleted ? 1 : progress
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let result = LineaGoal(
            id: existing?.id ?? UUID(),
            title: trimmedTitle,
            progress: isCompleted ? 1 : progress,
            isCompleted: isCompleted,
            createdAt: existing?.createdAt ?? Date()
        )
        Task {
            await plan.saveGoal(result)
            dismiss()
        }
    }
}
