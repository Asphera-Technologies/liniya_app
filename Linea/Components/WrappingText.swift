//
//  WrappingText.swift
//  Linea
//
//  Многострочный текст, который меряется и рисуется одним движком (UILabel)
//  при одной и той же ширине: высота всегда та, что нужна нарисованному
//  тексту. SwiftUI `Text` у причины «Сейчас» — «До встречи 23 мин — на это
//  хватит, а «Подготовить стратегию» лучше после встречи.» — мерил две
//  строки, а рисовал три и обрезал третью многоточием (видно на скриншотах
//  UI-тестов).
//

import SwiftUI
import UIKit

struct WrappingText: UIViewRepresentable {
    let text: String
    var textStyle: UIFont.TextStyle = .body
    var color: Color = LineaColor.textPrimary
    /// Что читает VoiceOver и видят UI-тесты; по умолчанию — сам текст.
    var accessibilityText: String? = nil

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.text = text
        label.font = UIFont.preferredFont(forTextStyle: textStyle)
        label.textColor = UIColor(color)
        label.accessibilityLabel = accessibilityText ?? text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitting.height))
    }
}
