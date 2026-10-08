//
//  WrappingText.swift
//  Linea
//
//  Многострочный текст, который меряется и рисуется одним и тем же
//  менеджером раскладки (TextKit 1) при одной и той же ширине: высота всегда
//  та, что нужна нарисованному тексту, и слова не переносятся по слогам.
//
//  Зачем не SwiftUI `Text`: причину «Сейчас» — «До встречи 23 мин — на это
//  хватит, а «Подготовить стратегию» лучше после встречи.» — он мерил на
//  строку короче, чем рисовал, и обрезал многоточием. Зачем не UILabel: тот
//  сам ставит русские переносы («Под-готовить») и не слушает стиль абзаца.
//  Всё видно на скриншотах UI-тестов.
//

import SwiftUI
import UIKit

struct WrappingText: UIViewRepresentable {
    let text: String
    var textStyle: UIFont.TextStyle = .body
    var color: Color = LineaColor.textPrimary
    /// Что читает VoiceOver и видят UI-тесты; по умолчанию — сам текст.
    var accessibilityText: String? = nil

    func makeUIView(context: Context) -> TextLayoutView {
        TextLayoutView()
    }

    func updateUIView(_ view: TextLayoutView, context: Context) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        // Ноль у абзаца и у менеджера раскладки — переносов по слогам нет.
        paragraph.usesDefaultHyphenation = false
        paragraph.hyphenationFactor = 0
        view.text = NSAttributedString(string: text, attributes: [
            .font: UIFont.preferredFont(forTextStyle: textStyle),
            .foregroundColor: UIColor(color),
            .paragraphStyle: paragraph,
        ])
        view.accessibilityLabel = accessibilityText ?? text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: TextLayoutView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return CGSize(width: width, height: uiView.height(forWidth: width))
    }
}

/// Текст на TextKit 1: одна раскладка и для высоты, и для рисования.
final class TextLayoutView: UIView {
    private let storage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let container = NSTextContainer(size: .zero)

    var text = NSAttributedString() {
        didSet {
            storage.setAttributedString(text)
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        container.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        // Тёмная тема: цвет текста динамический — перерисовать.
        _ = registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TextLayoutView, _: UITraitCollection) in
            view.setNeedsDisplay()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Высота текста при этой ширине — по той же раскладке, что и рисование.
    func height(forWidth width: CGFloat) -> CGFloat {
        container.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        return ceil(layoutManager.usedRect(for: container).height)
    }

    override func draw(_ rect: CGRect) {
        container.size = CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
        let glyphs = layoutManager.glyphRange(for: container)
        layoutManager.drawBackground(forGlyphRange: glyphs, at: .zero)
        layoutManager.drawGlyphs(forGlyphRange: glyphs, at: .zero)
    }
}
