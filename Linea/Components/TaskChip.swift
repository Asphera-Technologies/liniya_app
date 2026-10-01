//
//  TaskChip.swift
//  Linea
//
//  Чип параметра задачи под строкой ввода: «Сегодня», «~30 мин», «Средний».
//  Спокойная капсула на светлой заливке. Значение, которое человек не задавал
//  (Linea подставила сама), — серое: видно, что его можно не трогать.
//

import SwiftUI

struct TaskChip: View {
    let systemImage: String
    let title: String
    /// Значение по умолчанию или догадка Linea — серым.
    var isMuted: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.medium))
            Text(title)
                .font(LineaFont.caption)
                .lineLimit(1)
        }
        .foregroundStyle(isMuted ? LineaColor.textSecondary : LineaColor.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule(style: .continuous).fill(LineaColor.fill))
        .contentShape(Capsule(style: .continuous))
    }
}
