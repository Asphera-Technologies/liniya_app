//
//  LineaTextField.swift
//  Linea
//
//  A calm text field for Linea's editor sheets: plain background, a single
//  hairline underline. Deliberately not a boxed `Form` field, to keep editors
//  feeling like Linea rather than a generic settings screen.
//

import SwiftUI

struct LineaTextField: View {
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal
    /// Крупно — для названий; рассказ и ответы — шрифтом строки.
    var font: Font = LineaFont.feature
    /// Идентификатор самого поля — по нему его находят UI-тесты.
    var identifier: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            input
            LineaHairline()
        }
    }

    @ViewBuilder
    private var input: some View {
        let field = TextField(placeholder, text: $text, axis: axis)
            .font(font)
            .foregroundStyle(LineaColor.textPrimary)
            .tint(LineaColor.ink)
        if let identifier {
            field.accessibilityIdentifier(identifier)
        } else {
            field
        }
    }
}
