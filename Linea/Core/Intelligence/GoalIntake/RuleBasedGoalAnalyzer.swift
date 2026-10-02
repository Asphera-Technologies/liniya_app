//
//  RuleBasedGoalAnalyzer.swift
//  Linea
//
//  Разбор новой цели правилами, на телефоне. Рассказ режется на части
//  предложений, и каждая часть попадает в «Сейчас» или в «Результат»:
//  «уже есть», «сейчас идёт», «у нас» — это сейчас; «хотим, чтобы»,
//  «нужно», «будет» — это результат. Часть без таких слов, но с числом или
//  проверяемым признаком («доступно в TestFlight», «50 тестировщиков») —
//  результат, остальные идут за соседней частью.
//
//  Признаки успеха — проверяемые части результата: с числом или словом,
//  которое можно проверить («опубликовано», «подключить», «первая оплата»).
//  Их нет — Linea спрашивает «Как поймём, что цель достигнута?». Результат
//  есть, а «Сейчас» неизвестно — спрашивает, с чего начинаем. Не больше
//  одного вопроса за раз; ответ или «Пропустить» — и вопрос не повторяется.
//
//  Слова человека Linea не переписывает: только убирает служебное («хотим,
//  чтобы», «у нас», «было»), ставит заглавную букву и точку. Ничего, чего
//  человек не говорил, в цели не появляется.
//

import Foundation

nonisolated struct RuleBasedGoalAnalyzer: GoalAnalyzing {
    let parser: QuickTaskParser

    init(parser: QuickTaskParser = QuickTaskParser()) {
        self.parser = parser
    }

    func analyze(_ input: GoalIntakeInput, profile: UserProfile, time: TimeContext) async -> GoalUnderstanding {
        understand(input, profile: profile, time: time)
    }

    func understand(_ input: GoalIntakeInput, profile: UserProfile, time: TimeContext) -> GoalUnderstanding {
        let title = Self.title(input.title)

        var current: [String] = []
        var target: [String] = []
        var previous: Side?
        for sentence in Self.sentences(input.details) {
            for clause in Self.clauses(sentence) {
                let side = Self.side(of: clause)
                    ?? (Self.isMeasurable(clause) ? .target : previous ?? .current)
                switch side {
                case .current: current.append(clause)
                case .target: target.append(clause)
                }
                previous = side
            }
        }
        // Ответ — о том, о чём спросили, даже без слов-подсказок.
        let resultAnswer = Self.trimmed(input.answers[.result])
        let startAnswer = Self.trimmed(input.answers[.start])
        if let resultAnswer { target += Self.sentences(resultAnswer).flatMap(Self.clauses) }
        if let startAnswer { current += Self.sentences(startAnswer).flatMap(Self.clauses) }

        let targetTexts = target.map(Self.cleanTarget).filter { !$0.isEmpty }
        let currentTexts = current.map(Self.cleanCurrent).filter { !$0.isEmpty }

        var criteria = targetTexts.flatMap(Self.criteria)
        if criteria.isEmpty, Self.isMeasurable(title) { criteria = [title] }
        // На вопрос ответили, пусть и без чисел, — это и есть признак успеха.
        if criteria.isEmpty, resultAnswer != nil { criteria = targetTexts }

        var question: GoalQuestion?
        if criteria.isEmpty, resultAnswer == nil, !input.skipped.contains(.result) {
            question = .result
        } else if currentTexts.isEmpty, startAnswer == nil, !input.skipped.contains(.start) {
            question = .start
        }

        return GoalUnderstanding(
            title: title,
            currentState: Self.paragraph(currentTexts),
            targetState: Self.paragraph(targetTexts.isEmpty ? criteria : targetTexts),
            successCriteria: Self.unique(criteria),
            deadline: deadline(in: target + [input.title], profile: profile, time: time),
            details: Self.details(input),
            question: question
        )
    }

    // MARK: - Сейчас или результат

    nonisolated enum Side { case current, target }

    /// Слова желаемого: «хотим», «нужно», «чтобы», «будет», «результат».
    /// Короткие сравниваются целиком: «стать» — не «статья».
    static let targetWords: Set<String> = [
        "надо", "чтобы", "чтоб", "будет", "будут", "станет", "стать", "цель", "цели", "целью",
    ]
    static let targetStems = [
        "хоч", "хотим", "хотел", "нужн", "необходим", "должн", "итог", "результат", "достиг", "планиру",
        "собираюс", "собираем", "мечта", "добить", "добьюс",
    ]
    /// Слова того, что уже есть: «уже», «сейчас», «есть», «идёт», «сделали».
    /// «Пока» — целиком: не «показать».
    static let currentWords: Set<String> = [
        "уже", "сейчас", "пока", "есть", "имеется", "имеем", "идет", "идут", "работаем", "работаю",
        "делаем", "делаю", "было", "были", "был", "была",
    ]
    static let currentStems = [
        "сделал", "сделан", "готов", "переделыва", "переписыва", "дорабатыва", "начал", "начат",
        "написал", "собрал", "запустил",
    ]

    static func side(of clause: String) -> Side? {
        let words = Self.words(clause)
        func has(_ exact: Set<String>, _ stems: [String]) -> Bool {
            words.contains { word in exact.contains(word) || stems.contains { word.hasPrefix($0) } }
        }
        if has(targetWords, targetStems) { return .target }
        if has(currentWords, currentStems) { return .current }
        let text = " " + words.joined(separator: " ") + " "
        if text.contains(" у нас ") || text.contains(" у меня ") { return .current }
        return nil
    }

    // MARK: - Проверяемость

    static let numberWords: Set<String> = [
        "один", "одна", "одно", "одного", "одну", "два", "две", "двух", "три", "трех", "четыре", "пять", "пяти",
        "шесть", "семь", "восемь", "девять", "десять", "двадцать", "тридцать", "сорок", "пятьдесят",
        "шестьдесят", "семьдесят", "восемьдесят", "девяносто", "сто", "двести", "триста", "пятьсот",
    ]
    static let numberStems = ["тысяч", "миллион", "сотн", "десятк", "перв", "половин"]
    /// Признаки, которые можно проверить: опубликовано, подключено, оплачено.
    /// «Пользователи» без числа — не признак: «чтобы пользователям было удобно».
    static let verifiableStems = [
        "доступн", "опублик", "testflight", "релиз", "выпуст", "выпущ", "запущен", "подключ", "зарегистр",
        "оплат", "продаж", "выручк", "сдать", "сдан", "сдал", "сертифик", "оффер", "переех", "подписан",
        "защит",
    ]
    static let verifiablePhrases = ["app store", "google play"]

    static func isMeasurable(_ text: String) -> Bool {
        let words = Self.words(text)
        for word in words {
            if word.contains(where: \.isNumber) || numberWords.contains(word) { return true }
            if numberStems.contains(where: { word.hasPrefix($0) }) { return true }
            if verifiableStems.contains(where: { word.hasPrefix($0) }) { return true }
        }
        let joined = words.joined(separator: " ")
        return verifiablePhrases.contains { joined.contains($0) }
    }

    /// Признаки успеха в части результата: каждая проверяемая часть
    /// «… и …», «…, …» — отдельно.
    static func criteria(in text: String) -> [String] {
        let parts = text.components(separatedBy: ", ").flatMap { $0.components(separatedBy: " и ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let measurable = parts.filter(isMeasurable)
        if !measurable.isEmpty { return measurable.map(sentenceCase) }
        return isMeasurable(text) ? [sentenceCase(text)] : []
    }

    // MARK: - Срок

    /// Срок из того, что сказано о результате: «к 1 декабря», «до 25 числа».
    func deadline(in texts: [String], profile: UserProfile, time: TimeContext) -> Date? {
        for text in texts {
            if let deadline = parser.parse(text, profile: profile, time: time).deadline, deadline > time.now {
                return deadline
            }
        }
        return nil
    }

    // MARK: - Текст

    /// Название: без «хочу», «нужно» в начале и точки в конце, с заглавной.
    static func title(_ raw: String) -> String {
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let stripped = stripLeading(collapsed, phrases: ["я хочу", "мы хотим", "хочу", "хотим", "мне нужно", "нам нужно",
                                                        "нужно", "надо", "цель"])
        return sentenceCase(stripped.isEmpty ? collapsed : stripped)
    }

    static func cleanTarget(_ clause: String) -> String {
        let stripped = stripLeading(clause, phrases: [
            "в итоге", "в результате", "хотелось бы", "мне нужно", "нам нужно", "мне надо", "нам надо",
            "я хочу", "мы хотим", "хочу", "хотим", "хочется", "нужно", "надо", "необходимо", "чтобы", "чтоб",
            "цель", "результат", "и", "а", "но", "также", "еще", "ещё", "планирую", "планируем",
            "собираюсь", "собираемся", "это",
        ])
        // «Приложение было доступно» → «Приложение доступно».
        let auxiliary: Set<String> = ["было", "была", "были", "был", "будет", "будут", "стало", "стала"]
        let words = stripped.split(separator: " ").filter { word in
            !auxiliary.contains(RussianWords.normalized(word.trimmingCharacters(in: .punctuationCharacters)))
        }
        return sentenceCase(words.joined(separator: " "))
    }

    static func cleanCurrent(_ clause: String) -> String {
        let stripped = stripLeading(clause, phrases: [
            "у нас", "у меня", "сейчас", "на данный момент", "на сегодня", "и", "а", "но", "также",
        ])
        return sentenceCase(stripped)
    }

    /// Части через точку, каждая с заглавной.
    static func paragraph(_ texts: [String]) -> String? {
        let parts = unique(texts.map(sentenceCase).filter { !$0.isEmpty })
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ". ") + "."
    }

    /// Рассказ как есть: описание и ответы с вопросами.
    static func details(_ input: GoalIntakeInput) -> String? {
        var parts: [String] = []
        if let details = trimmed(input.details) { parts.append(details) }
        for topic in GoalQuestion.Topic.allCases {
            if let answer = trimmed(input.answers[topic]) {
                parts.append("\(GoalQuestion.about(topic).text) \(answer)")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    // MARK: - Разбиение

    /// Предложения. Точка и запятая между цифрами — часть числа: «2.5», «2,5».
    static func sentences(_ text: String) -> [String] {
        cut(text, at: ".!?…;\n")
    }

    /// Части предложения через запятую и тире. Придаточное («, чтобы …»,
    /// «, который …») остаётся со своей частью.
    static func clauses(_ sentence: String) -> [String] {
        let subordinate: Set<String> = [
            "чтобы", "чтоб", "что", "чем", "как", "кто", "где", "куда", "когда", "если", "потому", "почему", "зачем",
            "который", "которая", "которое", "которые", "которых",
        ]
        var result: [String] = []
        for part in cut(sentence, at: ",").flatMap({ $0.components(separatedBy: " — ") }).flatMap({ $0.components(separatedBy: " – ") }) {
            let piece = part.trimmingCharacters(in: .whitespaces)
            guard !piece.isEmpty else { continue }
            let first = words(piece).first ?? ""
            if subordinate.contains(first), let last = result.popLast() {
                result.append("\(last), \(piece)")
            } else {
                result.append(piece)
            }
        }
        return result
    }

    /// Режет по знакам, кроме точки и запятой между цифрами.
    static func cut(_ text: String, at marks: String) -> [String] {
        let characters = Array(text)
        var parts: [String] = []
        var current = ""
        for (index, character) in characters.enumerated() {
            let inNumber = (character == "." || character == ",")
                && index > 0 && characters[index - 1].isNumber
                && index + 1 < characters.count && characters[index + 1].isNumber
            if marks.contains(character) && !inNumber {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Слова строчными, «ё» → «е», без знаков.
    static func words(_ text: String) -> [String] {
        RussianWords.normalized(text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Снимает с начала служебные слова — по целым словам, пока снимается.
    static func stripLeading(_ text: String, phrases: [String]) -> String {
        var rest = text.trimmingCharacters(in: Self.edges)
        var changed = true
        while changed {
            changed = false
            let lowered = RussianWords.normalized(rest)
            for phrase in phrases.sorted(by: { $0.count > $1.count }) {
                let normalizedPhrase = RussianWords.normalized(phrase)
                guard lowered.hasPrefix(normalizedPhrase) else { continue }
                let after = lowered.dropFirst(normalizedPhrase.count)
                // Только целое слово: «надо» не снимается с «надоело».
                guard after.first.map({ !$0.isLetter && !$0.isNumber }) ?? true else { continue }
                rest = String(rest.dropFirst(normalizedPhrase.count)).trimmingCharacters(in: Self.edges)
                changed = true
                break
            }
        }
        return rest
    }

    /// Пробелы и знаки на краях части.
    static let edges = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",:—–-.;"))

    static func sentenceCase(_ text: String) -> String {
        RussianWords.capitalizedFirst(text.trimmingCharacters(in: edges))
    }

    static func trimmed(_ text: String?) -> String? {
        let value = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    static func unique(_ texts: [String]) -> [String] {
        var seen = Set<String>()
        return texts.filter { seen.insert(RussianWords.normalized($0)).inserted }
    }
}
