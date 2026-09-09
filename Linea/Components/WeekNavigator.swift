//
//  WeekNavigator.swift
//  Linea
//
//  A centered date-range label flanked by chevrons, used to page the Plan
//  screen between weeks (e.g. "‹  31 августа — 6 сентября  ›").
//

import SwiftUI

struct WeekNavigator: View {
    let title: String
    var onPrevious: () -> Void = {}
    var onNext: () -> Void = {}

    var body: some View {
        HStack {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.medium))
                    .foregroundStyle(LineaColor.textSecondary)
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Предыдущая неделя")

            Spacer(minLength: 0)
            Text(title)
                .font(LineaFont.rowTitle)
                .foregroundStyle(LineaColor.textPrimary)
            Spacer(minLength: 0)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.medium))
                    .foregroundStyle(LineaColor.textSecondary)
                    .frame(width: 44, height: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Следующая неделя")
        }
    }
}
