//
//  CheckInReviewView.swift
//  Linea
//
//  «Проверь»: что Linea поняла из рассказа. Ничего не меняется, пока человек
//  не нажал «Сохранить»: галочки у задач, сделанное сверх плана, объём, оценка
//  дня, что запомнить и перенос незакрытого — всё правится здесь.
//

import SwiftUI

struct CheckInReviewView: View {
    @Binding var draft: CheckInDraft
    /// Названия задач, которые уедут на завтра при включённом переносе.
    let moving: [String]
    let onEditStory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LineaMetrics.sectionSpacing) {
            header
            tasksSection
            if !draft.extra.isEmpty { extraSection }
            volumeSection
            ratingSection
            if !draft.memory.isEmpty { memorySection }
            moveSection
        }
    }

    // MARK: Шапка

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(draft.summary ?? "Проверь, всё ли понято верно, и поправь, если нужно.")
                .font(LineaFont.feature)
                .foregroundStyle(LineaColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Поправить рассказ", action: onEditStory)
                .font(LineaFont.control)
                .tint(LineaColor.textSecondary)
        }
    }

    // MARK: Задачи

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Задачи", trailing: draft.plannedCount > 0 ? "сделано \(draft.tasks.filter { $0.isPlannedForDay && $0.isDone }.count) из \(draft.plannedCount)" : nil)
            if draft.tasks.isEmpty {
                Text("На этот день задач не было.")
                    .font(LineaFont.rowTitle)
                    .foregroundStyle(LineaColor.textTertiary)
                    .padding(.vertical, 10)
            }
            ForEach($draft.tasks) { $line in
                CheckRow(
                    isOn: $line.isDone,
                    title: line.title,
                    detail: line.note,
                    isLocked: line.wasDone
                )
            }
        }
    }

    // MARK: Сверх плана

    private var extraSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Ещё сделано", trailing: "не из списка")
            ForEach($draft.extra) { $line in
                CheckRow(
                    isOn: $line.isIncluded,
                    title: line.title,
                    detail: line.minutes.map { RussianText.duration(minutes: $0) },
                    isLocked: false
                )
            }
        }
    }

    // MARK: Объём

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Объём работы", trailing: draft.statedWorkMinutes != nil ? "по твоим словам" : "по оценкам задач")
            Stepper(value: workMinutes, in: 0...(16 * 60), step: 30) {
                Text(draft.workMinutes.map { RussianText.duration(minutes: $0) } ?? "не знаю")
                    .font(LineaFont.rowTitle)
                    .foregroundStyle(LineaColor.textPrimary)
            }
            .padding(.vertical, 8)
        }
    }

    /// Поправленный человеком объём становится «со слов».
    private var workMinutes: Binding<Int> {
        Binding(
            get: { draft.workMinutes ?? 0 },
            set: { draft.statedWorkMinutes = $0 }
        )
    }

    // MARK: Оценка дня

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Как прошёл день", trailing: draft.energy?.title)
            HStack(spacing: 10) {
                ForEach(DayRating.allCases, id: \.self) { rating in
                    Chip(title: rating.title, isSelected: draft.rating == rating) {
                        draft.rating = draft.rating == rating ? nil : rating
                    }
                }
            }
        }
    }

    // MARK: Память

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Запомнить", trailing: "видно в «Памяти»")
            ForEach($draft.memory) { $line in
                CheckRow(
                    isOn: $line.isAccepted,
                    title: line.candidate.text,
                    detail: line.candidate.isExplicit ? "по твоей просьбе" : line.candidate.kind.title.lowercased(),
                    isLocked: false
                )
            }
        }
    }

    // MARK: Перенос

    private var moveSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $draft.movesUnfinishedToTomorrow) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Незакрытое — на завтра")
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textPrimary)
                    Text(moving.isEmpty ? "Переносить нечего" : moving.map(RussianText.quoted).joined(separator: ", "))
                        .font(LineaFont.caption)
                        .foregroundStyle(LineaColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(LineaColor.ink)
            .disabled(moving.isEmpty)
            .padding(.vertical, 10)
        }
    }
}

/// Строка с галочкой: задача, сделанное сверх плана, факт для памяти.
private struct CheckRow: View {
    @Binding var isOn: Bool
    let title: String
    let detail: String?
    let isLocked: Bool

    var body: some View {
        Button {
            guard !isLocked else { return }
            isOn.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? LineaColor.ink : LineaColor.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .font(LineaFont.caption)
                            .foregroundStyle(LineaColor.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isLocked ? 0.6 : 1)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Выбор одного из трёх: «Отлично», «Нормально», «Тяжело».
private struct Chip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(LineaFont.control)
                .foregroundStyle(isSelected ? LineaColor.onInk : LineaColor.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: LineaMetrics.controlRadius, style: .continuous)
                        .fill(isSelected ? LineaColor.ink : LineaColor.background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LineaMetrics.controlRadius, style: .continuous)
                        .strokeBorder(LineaColor.separator, lineWidth: LineaMetrics.hairline)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
