//
//  LineaPrimaryButton.swift
//  Linea
//
//  Главная кнопка — залитая чёрным: «Продолжить», «Всё верно», вариант,
//  который подсказала Linea. Остальные рядом — `LineaOutlineButton`.
//

import SwiftUI

struct LineaPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    /// Во всю ширину — для кнопки внизу листа и списка вариантов.
    var fillsWidth = false
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(LineaFont.control)
            .foregroundStyle(LineaColor.onInk)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: LineaMetrics.controlRadius, style: .continuous)
                    .fill(LineaColor.ink)
            )
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
