//
//  MemoryCommand.swift
//  Linea
//
//  «Запомни, что по вторникам у меня зал в 19:00». Явная просьба запомнить
//  обрабатывается без модели и без сети — так же, как в OpenClaw фраза
//  «remember this» сразу записывается в файл памяти. Модель может ошибиться
//  или быть выключена, а просьба человека теряться не должна.
//

import Foundation

nonisolated enum MemoryCommand {

    /// Длинные раньше коротких: «имей в виду» проверяется до «учти».
    static let triggers = ["имейте в виду", "имей в виду", "на будущее", "запомните", "запомни", "учтите", "учти"]

    /// Все просьбы запомнить в рассказе.
    static func candidates(in text: String) -> [MemoryCandidate] {
        sentences(of: text).compactMap(candidate(inSentence:))
    }

    /// Сообщение в чате целиком — просьба запомнить: «Запомни: …».
    static func command(in text: String) -> MemoryCandidate? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = RussianWords.normalized(trimmed)
        guard triggers.contains(where: { lower.hasPrefix($0) }) else { return nil }
        return candidate(inSentence: trimmed)
    }

    // MARK: Разбор

    static func candidate(inSentence sentence: String) -> MemoryCandidate? {
        for trigger in triggers {
            guard let range = wordRange(of: trigger, in: sentence) else { continue }
            let after = clean(String(sentence[range.upperBound...]))
            let before = clean(String(sentence[..<range.lowerBound]))
            // «Запомни, что …» — факт после просьбы; «…, запомни» — перед ней.
            let text = isMeaningful(after) ? after : before
            guard isMeaningful(text) else { return nil }
            let fact = RussianWords.capitalizedFirst(text)
            return MemoryCandidate(text: fact, kind: kind(of: fact), isExplicit: true)
        }
        return nil
    }

    /// Вхождение просьбы целым словом: «запомнил» — не просьба.
    private static func wordRange(of trigger: String, in sentence: String) -> Range<String.Index>? {
        var searchStart = sentence.startIndex
        while searchStart < sentence.endIndex,
              let range = sentence.range(of: trigger, options: [.caseInsensitive], range: searchStart..<sentence.endIndex) {
            let beforeOK = range.lowerBound == sentence.startIndex || !sentence[sentence.index(before: range.lowerBound)].isLetter
            let afterOK = range.upperBound == sentence.endIndex || !sentence[range.upperBound].isLetter
            if beforeOK && afterOK { return range }
            searchStart = range.upperBound
        }
        return nil
    }

    private static let leadingNoise = ["пожалуйста", "что", "то"]

    private static func clean(_ text: String) -> String {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",:;—–-.!?«»\""))
        var result = text.trimmingCharacters(in: separators)
        var changed = true
        while changed {
            changed = false
            for word in leadingNoise {
                let lower = RussianWords.normalized(result)
                guard lower.hasPrefix(word + " ") || lower.hasPrefix(word + ",") || lower == word else { continue }
                result = String(result.dropFirst(word.count)).trimmingCharacters(in: separators)
                changed = true
            }
        }
        return result
    }

    private static func isMeaningful(_ text: String) -> Bool {
        text.count >= 8 && RussianWords.tokens(text).count >= 2
    }

    /// Разбиение на предложения, не ломающее «2.5» и «19.00».
    private static func sentences(of text: String) -> [String] {
        let characters = Array(text)
        var result: [String] = []
        var current = ""
        for (index, character) in characters.enumerated() {
            current.append(character)
            let isTerminator = ".!?;\n".contains(character)
            let nextIsBreak = index + 1 >= characters.count || characters[index + 1].isWhitespace
            if isTerminator && nextIsBreak {
                result.append(current)
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(current) }
        return result
    }

    // MARK: Вид факта

    private static let constraintWords: Set<String> = ["нельзя", "никогда", "аллергия", "запрещено"]
    private static let constraintPhrases: [[String]] = [["не", "могу"], ["не", "ем"], ["не", "пью"], ["не", "работаю"], ["не", "беру"]]
    private static let patternWords: Set<String> = [
        "обычно", "всегда", "каждый", "каждую", "каждое", "каждые", "утрам", "вечерам",
        "понедельникам", "вторникам", "средам", "четвергам", "пятницам", "субботам",
        "воскресеньям", "выходным", "будням", "часто", "регулярно",
    ]
    private static let patternPhrases: [[String]] = [["после", "обеда"], ["до", "обеда"], ["к", "вечеру"], ["с", "утра"]]
    private static let preferenceWords: Set<String> = [
        "люблю", "любит", "нравится", "нравятся", "предпочитаю", "предпочитает", "удобнее", "лучше", "хочу", "хочет", "комфортнее",
    ]

    static func kind(of text: String) -> MemoryFactKind {
        let words = RussianWords.tokens(text).map(\.normalized)
        if words.contains(where: constraintWords.contains) || CheckInText.contains(words, anyOf: constraintPhrases) {
            return .constraint
        }
        if words.contains(where: patternWords.contains) || CheckInText.contains(words, anyOf: patternPhrases) { return .pattern }
        if words.contains(where: preferenceWords.contains) { return .preference }
        return .context
    }
}
