//
//  CaptureTokenizer.swift
//  Linea
//
//  Строка быстрого ввода → слова, числа, время на часах и даты, у каждого
//  куска — место в исходной строке. Место нужно, чтобы вырезать из названия
//  ровно то, что стало параметром, а остальное оставить как написано.
//

import Foundation

nonisolated struct CaptureToken: Hashable, Sendable {
    nonisolated enum Kind: Hashable, Sendable {
        case word
        case number(Double)
        /// «15:00».
        case clock(TimeOfDay)
        /// «15.10», «15.10.2026».
        case date(day: Int, month: Int, year: Int?)
        /// «!».
        case mark
        /// Запятая, тире, двоеточие.
        case pause
        /// Точка, вопрос, точка с запятой, перевод строки.
        case end
    }

    let kind: Kind
    /// Слово строчными, «ё» → «е»; число — как его читает `CheckInText`
    /// («2.5»). У времени, даты и знаков — пустая строка: для словарей они
    /// не слова и не числа.
    let word: String
    let range: Range<String.Index>

    /// Может остаться в названии задачи.
    var isText: Bool {
        switch kind {
        case .word, .number, .clock, .date: return true
        case .mark, .pause, .end: return false
        }
    }
}

nonisolated enum CaptureTokenizer {

    static func tokens(_ text: String) -> [CaptureToken] {
        var result: [CaptureToken] = []
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character.isLetter {
                let end = wordEnd(in: text, from: index)
                result.append(CaptureToken(kind: .word, word: RussianWords.normalized(String(text[index..<end])), range: index..<end))
                index = end
            } else if isDigit(character) {
                let token = number(in: text, from: index)
                result.append(token)
                index = token.range.upperBound
            } else {
                let end = text.index(after: index)
                if character == "!" {
                    result.append(CaptureToken(kind: .mark, word: "", range: index..<end))
                } else if character.isNewline || ".?;…".contains(character) {
                    if result.last?.kind != .end {
                        result.append(CaptureToken(kind: .end, word: "", range: index..<end))
                    }
                } else if ",—–:-".contains(character) {
                    result.append(CaptureToken(kind: .pause, word: "", range: index..<end))
                }
                index = end
            }
        }
        return result
    }

    static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    /// «когда-нибудь», «из-за»: дефис между буквами — часть слова.
    private static func wordEnd(in text: String, from start: String.Index) -> String.Index {
        var end = text.index(after: start)
        while end < text.endIndex {
            if text[end].isLetter {
                end = text.index(after: end)
            } else if text[end] == "-", let next = text.index(end, offsetBy: 1, limitedBy: text.endIndex),
                      next < text.endIndex, text[next].isLetter {
                end = next
            } else {
                break
            }
        }
        return end
    }

    private static func digits(in text: String, from start: String.Index) -> (String, String.Index) {
        var end = start
        while end < text.endIndex, isDigit(text[end]) { end = text.index(after: end) }
        return (String(text[start..<end]), end)
    }

    /// Цифры сразу после разделителя, если разделитель стоит в `index`.
    private static func digits(after separator: Character, at index: String.Index, in text: String) -> (String, String.Index)? {
        guard index < text.endIndex, text[index] == separator else { return nil }
        let next = text.index(after: index)
        guard next < text.endIndex, isDigit(text[next]) else { return nil }
        return digits(in: text, from: next)
    }

    /// Число, время «15:00», дата «15.10.2026» или дробь «1,5».
    private static func number(in text: String, from start: String.Index) -> CaptureToken {
        let (first, afterFirst) = digits(in: text, from: start)

        if let (minutes, end) = digits(after: ":", at: afterFirst, in: text),
           minutes.count == 2, let hour = Int(first), let minute = Int(minutes), hour <= 23, minute <= 59 {
            return CaptureToken(kind: .clock(TimeOfDay(hour: hour, minute: minute)), word: "", range: start..<end)
        }

        // «15.10» — дата, «1.5» — дробь: у месяца всегда две цифры.
        if let (month, afterMonth) = digits(after: ".", at: afterFirst, in: text),
           first.count <= 2, month.count == 2, let day = Int(first), let monthValue = Int(month),
           (1...31).contains(day), (1...12).contains(monthValue) {
            if let (year, afterYear) = digits(after: ".", at: afterMonth, in: text),
               year.count == 2 || year.count == 4, let yearValue = Int(year) {
                let fullYear = year.count == 2 ? 2000 + yearValue : yearValue
                return CaptureToken(kind: .date(day: day, month: monthValue, year: fullYear), word: "", range: start..<afterYear)
            }
            return CaptureToken(kind: .date(day: day, month: monthValue, year: nil), word: "", range: start..<afterMonth)
        }

        for separator: Character in [".", ","] {
            if let (fraction, end) = digits(after: separator, at: afterFirst, in: text),
               let value = Double("\(first).\(fraction)") {
                return CaptureToken(kind: .number(value), word: "\(first).\(fraction)", range: start..<end)
            }
        }
        return CaptureToken(kind: .number(Double(first) ?? 0), word: first, range: start..<afterFirst)
    }
}
