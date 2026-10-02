//
//  LineaOutlineButton.swift
//  Linea
//
//  The quiet bordered button used across Linea (e.g. "Подобрать",
//  "Составить меню на неделю"). Outline, not filled, to keep the interface
//  calm; ink fill is reserved for selection states.
//

import SwiftUI

struct LineaOutlineButton: View {
    let title: String
    /// Во всю ширину — для списка вариантов.
    var fillsWidth = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(LineaFont.control)
                .foregroundStyle(LineaColor.textPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .background(
                    RoundedRectangle(cornerRadius: LineaMetrics.controlRadius, style: .continuous)
                        .fill(LineaColor.background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LineaMetrics.controlRadius, style: .continuous)
                        .strokeBorder(LineaColor.separator, lineWidth: LineaMetrics.hairline)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
