//
//  GoalSuggestionRow.swift
//  Linea
//
//  «Похоже, относится к: Запустить Линия Beta [Связать]» — Linea нашла
//  вероятную цель задачи и тихо предлагает связь. Связывает только человек;
//  ничего не нажал — задача спокойно живёт без цели. Одинаково в быстром
//  вводе и в карточке задачи.
//

import SwiftUI

struct GoalSuggestionRow: View {
    let goalTitle: String
    var onLink: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Похоже, относится к:")
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textSecondary)
                Text(goalTitle)
                    .font(LineaFont.rowTitle)
                    .foregroundStyle(LineaColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("goalSuggestion.title")
            }
            Spacer(minLength: 8)
            Button(action: onLink) {
                Text("Связать")
                    .font(LineaFont.control)
                    .foregroundStyle(LineaColor.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(LineaColor.separator, lineWidth: LineaMetrics.hairline)
                    )
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Связать с целью «\(goalTitle)»")
            .accessibilityIdentifier("goalSuggestion.link")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("goalSuggestion")
    }
}
