//
//  SectionLabel.swift
//  Linea
//
//  A quiet gray section label, optionally with a trailing note on the right
//  (e.g. "Демо" / "Демо-данные").
//

import SwiftUI

struct SectionLabel: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(LineaFont.sectionLabel)
                .foregroundStyle(LineaColor.textSecondary)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(LineaFont.sectionLabel)
                    .foregroundStyle(LineaColor.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
