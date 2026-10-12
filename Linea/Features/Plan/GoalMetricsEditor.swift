//
//  GoalMetricsEditor.swift
//  Linea
//
//  Числа цели в карточке: «Что считаем», «Было», «Сейчас», «Цель». Одни и те
//  же — для прогресса цели и для своей части в цели команды (ADR-038):
//  общее число и своё число — разные списки, правятся одинаково. Поля чисел
//  меняют значение на каждый символ (`LineaNumberField`).
//

import SwiftUI

struct GoalMetricsEditor: View {
    @Binding var metrics: [GoalMetric]
    /// Сколько чисел видно; nil — все, и их можно добавлять и убирать.
    var limit: Int?
    /// «Что считаем» — первое число, «Ещё число» — следующие.
    var firstAddTitle = "Что считаем"
    var nextAddTitle = "Ещё число"
    var unitPlaceholder = "Что считаем: пользователей, км, ₽"
    /// Начало идентификаторов для UI-тестов: «goal.metric», «goal.contribution».
    var identifier = "goal.metric"

    var body: some View {
        let shown = limit.map { Array(metrics.prefix($0)) } ?? metrics
        VStack(alignment: .leading, spacing: 18) {
            ForEach(shown) { metric in
                row(metric, removable: limit == nil)
            }
            if limit == nil || metrics.isEmpty {
                Button {
                    withAnimation(.snappy) {
                        metrics.append(GoalMetric(id: UUID(), unit: "", target: 0))
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.footnote.weight(.medium))
                        Text(metrics.isEmpty ? firstAddTitle : nextAddTitle)
                            .font(LineaFont.rowTitle)
                    }
                    .foregroundStyle(LineaColor.textTertiary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(identifier).add")
            }
        }
    }

    private func row(_ metric: GoalMetric, removable: Bool) -> some View {
        let binding = metricBinding(metric.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 12) {
                LineaTextField(placeholder: unitPlaceholder, text: binding.unit, font: LineaFont.rowTitle,
                               identifier: "\(identifier).unit")
                if removable {
                    Button {
                        withAnimation(.snappy) { metrics.removeAll { $0.id == metric.id } }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(LineaColor.textTertiary)
                            .padding(.bottom, 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Убрать число")
                }
            }
            // Значение меняется на каждый символ: «18» и сразу «Готово» — сохранится 18.
            HStack(alignment: .top, spacing: 16) {
                LineaNumberField(label: "Было", value: binding.start, identifier: "\(identifier).start")
                LineaNumberField(label: "Сейчас", value: binding.current, identifier: "\(identifier).current")
                LineaNumberField(label: "Цель", value: binding.target, identifier: "\(identifier).target")
            }
        }
    }

    /// По id, а не по индексу: убранное число не уронит строку, которая ещё рисуется.
    private func metricBinding(_ id: UUID) -> Binding<GoalMetric> {
        Binding(
            get: { metrics.first { $0.id == id } ?? GoalMetric(id: id, unit: "", target: 0) },
            set: { value in
                guard let index = metrics.firstIndex(where: { $0.id == id }) else { return }
                metrics[index] = value
            }
        )
    }
}
