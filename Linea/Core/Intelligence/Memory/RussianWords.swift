//
//  RussianWords.swift
//  Linea
//
//  Слова русской речи для разбора рассказа и поиска по памяти. Без словарей
//  и морфологии: слово обрезается до основы фиксированной длины, как в
//  `KeywordGoalMatcher`, этого хватает, чтобы «презентацию» узнать в задаче
//  «Презентация КП». Работает офлайн, одинаково на Linux и на телефоне.
//

import Foundation

nonisolated struct SpokenToken: Hashable, Sendable {
    /// Как было сказано — для названий, которые увидит человек.
    let original: String
    /// Строчными, «ё» → «е» — для сравнения.
    let normalized: String
    let isNumber: Bool
}

nonisolated enum RussianWords {

    static func normalized(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    /// Слова и числа по порядку. «2,5» и «2.5» остаются одним числом.
    static func tokens(_ text: String) -> [SpokenToken] {
        pieces(text).compactMap { piece in
            if case .token(let token) = piece { return token }
            return nil
        }
    }

    /// Слова, по которым имеет смысл искать: без служебных и коротких.
    static func significant(_ text: String, minimumLength: Int = 3) -> [String] {
        tokens(text)
            .filter { !$0.isNumber }
            .map(\.normalized)
            .filter { $0.count >= minimumLength && !stopWords.contains($0) }
    }

    /// Основа слова: окончание отрезается, приставка остаётся. Короткие слова
    /// («зал», «бег») берутся целиком.
    static func stem(_ word: String) -> String {
        let word = normalized(word)
        guard word.count > 3 else { return word }
        return String(word.prefix(min(5, word.count - 1)))
    }

    static func stems(_ text: String) -> Set<String> {
        Set(significant(text).map(stem))
    }

    /// Несёт ли сказанное слово основу из названия. Помимо совпадения начала
    /// ловит приставочные глаголы: «тренировка» → «потренировался».
    static func word(_ word: String, matches stem: String) -> Bool {
        guard !stem.isEmpty else { return false }
        if word.hasPrefix(stem) {
            // Короткую основу («пла» из «план») не пускаем в длинные слова.
            return stem.count >= 4 || word.count <= stem.count + 3
        }
        // «по» + «тренировался»: приставка и возвратное окончание вместе дают до десяти букв.
        return stem.count >= 5 && word.count <= stem.count + 10 && word.contains(stem)
    }

    /// Жаккар по основам: доля общих основ двух текстов.
    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let a = stems(lhs)
        let b = stems(rhs)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }

    /// Первая буква заглавная, остальное как было.
    static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    // MARK: Разбиение

    nonisolated enum Piece: Hashable, Sendable {
        case token(SpokenToken)
        /// Запятая или тире: граница части предложения.
        case pause
        /// Точка, вопрос, восклицание, точка с запятой, перевод строки.
        case sentenceEnd
    }

    static func pieces(_ text: String) -> [Piece] {
        let characters = Array(text)
        var result: [Piece] = []
        var current = ""
        var isNumber = false

        func flush() {
            guard !current.isEmpty else { return }
            result.append(.token(SpokenToken(original: current, normalized: normalized(current), isNumber: isNumber)))
            current = ""
            isNumber = false
        }

        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isNumber {
                if !current.isEmpty && !isNumber { flush() }
                isNumber = true
                current.append(character)
            } else if character.isLetter {
                if isNumber { flush() }
                current.append(character)
            } else if (character == "," || character == "."), isNumber,
                      index + 1 < characters.count, characters[index + 1].isNumber {
                // Десятичная дробь внутри числа.
                current.append(".")
            } else {
                flush()
                if ".!?;…\n".contains(character) {
                    if result.last != .sentenceEnd { result.append(.sentenceEnd) }
                } else if ",—–:".contains(character) {
                    result.append(.pause)
                }
            }
            index += 1
        }
        flush()
        return result
    }

    /// Служебные слова, по которым нельзя искать совпадения.
    static let stopWords: Set<String> = [
        "и", "в", "во", "на", "с", "со", "по", "к", "ко", "для", "от", "до", "за", "про",
        "о", "об", "обо", "у", "из", "а", "но", "же", "ли", "бы", "ну", "вот", "да", "не",
        "нет", "ни", "или", "либо", "это", "этот", "эта", "эти", "то", "тот", "та",
        "те", "как", "что", "чтобы", "где", "когда", "чем", "при", "над", "под", "без",
        "через", "после", "перед", "около", "между", "я", "ты", "он", "она", "оно", "мы",
        "вы", "они", "мне", "меня", "мной", "мой", "моя", "мое", "мои", "его", "ее", "их",
        "нам", "вам", "им", "себя", "свой", "своя", "свои", "сам", "сама", "там", "тут",
        "здесь", "еще", "уже", "очень", "так", "тоже", "также", "потом", "затем", "просто",
        "был", "была", "было", "были", "быть", "есть", "все", "весь", "вся", "всю", "всех",
        "день", "дня", "сегодня", "раз", "почти", "только", "какой", "какая", "какие",
        "сколько", "почему", "зачем", "последний", "последнее", "всего",
    ]
}
