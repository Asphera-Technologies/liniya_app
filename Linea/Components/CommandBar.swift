//
//  CommandBar.swift
//  Linea
//
//  Кнопка «Задать вопрос Linea», закреплённая над таб-баром на каждом экране.
//  Это точка входа в ассистента: не отдельная вкладка, а строка, которая всегда
//  под рукой.
//
//  На iOS 26 и новее используется Liquid Glass: кнопка становится стеклянной и
//  реагирует на нажатие. На более старых системах остаётся прежний спокойный
//  вид с волосяной рамкой — Linea не должна выглядеть сломанной там, где
//  стекла нет.
//

import SwiftUI

struct CommandBar: View {
    @Environment(AppState.self) private var appState

    private static let title = "Задать вопрос Linea"

    var body: some View {
        Button {
            appState.openAI()
        } label: {
            label
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.title)
        .accessibilityHint("Открывает Linea AI")
        .padding(.horizontal, LineaMetrics.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(LineaColor.background)
    }

    private var label: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.footnote.weight(.medium))
                .foregroundStyle(LineaColor.textSecondary)
            Text(Self.title)
                .font(LineaFont.rowTitle)
                .foregroundStyle(LineaColor.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(height: LineaMetrics.controlHeight)
        .modifier(CommandBarSurface())
        .contentShape(Rectangle())
    }
}

/// Поверхность кнопки: стекло на iOS 26, прежняя рамка на старых системах.
private struct CommandBarSurface: ViewModifier {
    private var shape: some Shape {
        RoundedRectangle(cornerRadius: LineaMetrics.surfaceRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content
                .background(shape.fill(LineaColor.background))
                .overlay(shape.strokeBorder(LineaColor.separator, lineWidth: LineaMetrics.hairline))
        }
    }
}
