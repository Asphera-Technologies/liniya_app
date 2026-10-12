//
//  LineaNumberField.swift
//  Linea
//
//  Поле для числа: «18», «2,5», «300 000». Значение меняется на каждый
//  набранный символ, а не когда поле теряет фокус: набрал «18» и сразу
//  нажал «Готово» — сохранится 18. С подписью сверху и линией снизу, как
//  остальные поля Linea.
//

import SwiftUI

struct LineaNumberField: View {
    let label: String
    /// nil — поле пустое (например, вес этапа не задан).
    @Binding var value: Double?
    var placeholder: String = "0"
    var identifier: String? = nil

    @State private var text: String

    init(label: String, value: Binding<Double?>, placeholder: String = "0", identifier: String? = nil) {
        self.label = label
        _value = value
        self.placeholder = placeholder
        self.identifier = identifier
        _text = State(initialValue: value.wrappedValue.map(GoalProgressText.number) ?? "")
    }

    /// Обязательное число: пусто — ноль.
    init(label: String, value: Binding<Double>, placeholder: String = "0", identifier: String? = nil) {
        self.init(
            label: label,
            value: Binding<Double?>(get: { value.wrappedValue }, set: { value.wrappedValue = $0 ?? 0 }),
            placeholder: placeholder,
            identifier: identifier
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !label.isEmpty {
                Text(label)
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textSecondary)
            }
            field
            LineaHairline()
        }
    }

    @ViewBuilder
    private var field: some View {
        let input = TextField(placeholder, text: $text)
            .keyboardType(.decimalPad)
            .font(LineaFont.rowTitle)
            .foregroundStyle(LineaColor.textPrimary)
            .tint(LineaColor.ink)
            .accessibilityLabel(label)
            .onChange(of: text) { _, typed in
                let parsed = GoalProgressText.parseNumber(typed)
                if parsed != value, parsed != nil || typed.isEmpty { value = parsed }
            }
            .onChange(of: value) { _, new in
                // Поменяли снаружи — показать; своё набранное («2,») не трогать.
                if GoalProgressText.parseNumber(text) != new { text = new.map(GoalProgressText.number) ?? "" }
            }
        if let identifier {
            input.accessibilityIdentifier(identifier)
        } else {
            input
        }
    }
}
