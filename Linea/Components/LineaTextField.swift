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

    var body: some View {
        VStack(spacing: 10) {
            TextField(placeholder, text: $text, axis: axis)
                .font(LineaFont.feature)
                .foregroundStyle(LineaColor.textPrimary)
                .tint(LineaColor.ink)
            LineaHairline()
        }
    }
}
