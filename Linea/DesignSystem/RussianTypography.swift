//
//  RussianTypography.swift
//  Linea
//
//  Неразрывные пробелы по правилам русской типографики: однобуквенные
//  союзы и предлоги («а», «в», «и», «к», «о», «с», «у», «я») не висят в
//  конце строки, тире не начинает строку: «…хватит, а «Подготовить
//  стратегию»…» переносится вместе с «а».
//
//  Только для показа: VoiceOver и UI-тесты получают исходный текст.
//

import Foundation

enum RussianTypography {
    /// Однобуквенные слова, которые держатся за следующее.
    static let shortWords: Set<String> = ["а", "в", "и", "к", "о", "с", "у", "я"]

    static func nonBreaking(_ text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        var result = ""
        for (index, word) in words.enumerated() {
            result += word
            guard index < words.count - 1 else { break }
            let next = words[index + 1]
            let holdsNext = shortWords.contains(word.lowercased())
            let dashFollows = next.hasPrefix("—") || next.hasPrefix("–")
            result += holdsNext || dashFollows ? "\u{00A0}" : " "
        }
        return result
    }
}
