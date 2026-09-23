//
//  CheckInText.swift
//  Linea
//
//  Как читать вечерний рассказ без модели: на что он делится, какие слова
//  значат «сделал», «не успел», «начал», как звучат длительности и оценка дня.
//  Словари намеренно небольшие и явные — их легко дополнить по жалобе
//  тестировщика, и каждое слово закреплено тестом.
//

import Foundation

// MARK: - Части предложения

/// Часть предложения между запятыми и союзами: «сделал отчёт», «а спортзал
/// не успел». Статус задачи решается внутри такой части.
nonisolated struct CheckInClause: Sendable {
    nonisolated enum Link: Sendable, Equatable {
        /// Первая часть предложения.
        case start
        /// «и», запятая, «потом», «ещё»: продолжает мысль, наследует статус.
        case continuation
        /// «а», «но», «зато»: противопоставление, статус не наследуется.
        case contrast
    }

    let tokens: [SpokenToken]
    let link: Link
    let sentence: Int

    var words: [String] { tokens.map(\.normalized) }
}

nonisolated enum CheckInText {

    static let continuationWords: Set<String> = ["и", "потом", "затем", "еще", "также", "плюс", "дальше", "далее"]
    static let contrastWords: Set<String> = ["а", "но", "однако", "зато", "хотя"]

    static func clauses(_ text: String) -> [CheckInClause] {
        var result: [CheckInClause] = []
        var current: [SpokenToken] = []
        var link: CheckInClause.Link = .start
        var sentence = 0

        func close(next: CheckInClause.Link) {
            if !current.isEmpty {
                result.append(CheckInClause(tokens: current, link: link, sentence: sentence))
                current = []
                link = next
            } else if next == .contrast {
                // «, а» — противопоставление сильнее запятой.
                link = .contrast
            }
        }

        for piece in RussianWords.pieces(text) {
            switch piece {
            case .sentenceEnd:
                close(next: .start)
                link = .start
                sentence += 1
            case .pause:
                close(next: .continuation)
            case .token(let token):
                if continuationWords.contains(token.normalized) {
                    close(next: .continuation)
                } else if contrastWords.contains(token.normalized) {
                    close(next: .contrast)
                } else {
                    current.append(token)
                }
            }
        }
        close(next: .start)
        return result
    }

    // MARK: - Статус

    /// «начал», «наполовину», «не до конца» — начато, но не закрыто.
    static let partialWords: Set<String> = [
        "частично", "наполовину", "половину", "почти", "начал", "начала", "начали",
        "начинал", "начинала", "приступил", "приступила", "продолжу", "доделаю",
        "допишу", "закончу", "осталось", "осталась",
    ]
    static let partialPhrases: [[String]] = [["не", "до", "конца"], ["не", "полностью"], ["не", "совсем"], ["в", "процессе"]]

    /// Основы, которые сами по себе значат «не сделал».
    static let negativeStems = ["перенес", "отлож", "отмен", "пропуст", "забыл", "провал", "сорвал", "сдался", "сдалась"]
    static let negativeWords: Set<String> = ["не", "нет", "ни", "ничего"]

    /// Основы глаголов «сделал». Совпадение по началу слова.
    static let positiveStems = [
        "сдела", "додела", "законч", "закры", "заверш", "выполн", "отправ", "сдал",
        "провел", "провела", "провели", "успел", "получил", "вышло", "удалось",
        "написал", "дописал", "подготовил", "ответил", "разобрал", "решил", "починил",
        "выложил", "запустил", "отработ", "поработ", "сходил", "съездил", "позанима",
        "потренир", "созвонил", "встретил", "обсудил", "согласовал", "купил", "оплатил",
        "собрал", "убрал", "прочитал", "изучил", "посмотрел", "отрисовал", "доделал",
    ]
    static let positiveWords: Set<String> = ["готово", "готова", "готов", "сделано", "закрыто"]

    /// Статус части предложения по её словам; `ignoring` — индексы слов из
    /// названия задачи («Подготовить отчёт» не должен сам себя отмечать).
    static func status(of words: [String], ignoring: Set<Int> = []) -> TaskOutcomeStatus? {
        let visible = words.enumerated().filter { !ignoring.contains($0.offset) }.map(\.element)
        guard !visible.isEmpty else { return nil }

        if visible.contains(where: partialWords.contains) || contains(visible, anyOf: partialPhrases) {
            return .partial
        }
        if visible.contains(where: negativeWords.contains)
            || visible.contains(where: { word in negativeStems.contains { word.hasPrefix($0) } }) {
            return .notDone
        }
        if visible.contains(where: positiveWords.contains)
            || visible.contains(where: { word in positiveStems.contains { word.hasPrefix($0) } }) {
            return .done
        }
        return nil
    }

    static func contains(_ words: [String], anyOf phrases: [[String]]) -> Bool {
        phrases.contains { phrase in
            guard phrase.count <= words.count else { return false }
            return (0...(words.count - phrase.count)).contains { start in
                Array(words[start..<(start + phrase.count)]) == phrase
            }
        }
    }

    // MARK: - Длительности

    nonisolated struct Duration: Sendable, Equatable {
        let minutes: Int
        /// Индексы слов, из которых сложилась длительность.
        let range: ClosedRange<Int>
    }

    /// Единица «час» в единственном числе: «час двадцать» — это 1:20.
    static let singleHourWords: Set<String> = ["час", "часик"]
    static let hourWords: Set<String> = ["час", "часа", "часов", "часик", "часика", "часиков", "ч"]
    static let minuteWords: Set<String> = ["минут", "минуты", "минуту", "минутка", "минутку", "минуток", "мин"]
    /// Предлоги, после которых «в два часа» — время на часах, а не длительность.
    static let clockPrepositions: Set<String> = ["в", "к", "до", "после", "с", "со"]

    static let numberWords: [String: Double] = [
        "один": 1, "одна": 1, "одну": 1, "одного": 1, "два": 2, "две": 2, "двух": 2,
        "три": 3, "трех": 3, "четыре": 4, "четырех": 4, "пять": 5, "пяти": 5, "шесть": 6,
        "шести": 6, "семь": 7, "семи": 7, "восемь": 8, "восьми": 8, "девять": 9,
        "девяти": 9, "десять": 10, "десяти": 10, "одиннадцать": 11, "двенадцать": 12,
        "пятнадцать": 15, "двадцать": 20, "двадцати": 20, "тридцать": 30, "тридцати": 30,
        "сорок": 40, "сорока": 40, "пятьдесят": 50, "пятидесяти": 50, "полтора": 1.5,
        "полторы": 1.5, "пару": 2, "пара": 2, "пары": 2,
    ]

    static func isUnit(_ word: String) -> Bool { hourWords.contains(word) || minuteWords.contains(word) }

    /// Число, начинающееся с этого слова: «3», «2.5», «три», «двадцать пять».
    static func number(at index: Int, in words: [String]) -> (value: Double, range: ClosedRange<Int>)? {
        guard words.indices.contains(index) else { return nil }
        let word = words[index]
        if word.first?.isNumber == true, let value = Double(word) { return (value, index...index) }
        guard let value = numberWords[word] else { return nil }
        if value >= 20, value.truncatingRemainder(dividingBy: 10) == 0,
           words.indices.contains(index + 1), let unit = numberWords[words[index + 1]], unit < 10 {
            return (value + unit, index...(index + 1))
        }
        return (value, index...index)
    }

    /// Число, которое заканчивается на этом слове (учитывая «двадцать пять»).
    static func number(endingAt index: Int, in words: [String]) -> (value: Double, range: ClosedRange<Int>)? {
        if index >= 1, let compound = number(at: index - 1, in: words), compound.range.upperBound == index {
            return compound
        }
        guard let single = number(at: index, in: words), single.range.upperBound == index else { return nil }
        return single
    }

    /// Все длительности в части текста: «3 часа», «часа три», «полтора часа»,
    /// «два с половиной часа», «час двадцать», «40 минут», «полчаса».
    static func durations(in words: [String]) -> [Duration] {
        var found: [Duration] = []
        for index in words.indices {
            let word = words[index]
            if let last = found.last, last.range.contains(index) { continue }
            if word == "полчаса" || word == "полчасика" {
                found.append(Duration(minutes: 30, range: index...index))
            } else if word == "полдня" {
                found.append(Duration(minutes: 240, range: index...index))
            } else if isUnit(word), let duration = duration(unitAt: index, in: words) {
                found.append(duration)
            }
        }
        return merged(found)
    }

    private static func duration(unitAt index: Int, in words: [String]) -> Duration? {
        let unit = words[index]
        let perUnit: Double = hourWords.contains(unit) ? 60 : 1

        // «два с половиной часа»
        if index >= 3, words[index - 1].hasPrefix("половин"), words[index - 2] == "с",
           let base = number(endingAt: index - 3, in: words) {
            guard !isClockTime(before: base.range.lowerBound, in: words) else { return nil }
            return Duration(minutes: Int(((base.value + 0.5) * perUnit).rounded()), range: base.range.lowerBound...index)
        }

        // «3 часа», «полтора часа», «40 минут»; дальше может идти «с половиной»
        // или минуты без слова «минут»: «два часа двадцать».
        if index >= 1, let base = number(endingAt: index - 1, in: words) {
            guard !isClockTime(before: base.range.lowerBound, in: words) else { return nil }
            var minutes = base.value * perUnit
            var upper = index
            if index + 2 < words.count, words[index + 1] == "с", words[index + 2].hasPrefix("половин") {
                minutes += 0.5 * perUnit
                upper = index + 2
            } else if perUnit == 60, let tail = number(at: index + 1, in: words), tail.value < 60,
                      !(words.indices.contains(tail.range.upperBound + 1) && isUnit(words[tail.range.upperBound + 1])) {
                minutes += tail.value
                upper = tail.range.upperBound
            }
            return Duration(minutes: Int(minutes.rounded()), range: base.range.lowerBound...upper)
        }

        guard !isClockTime(before: index, in: words) else { return nil }
        // «минут на сорок», «часа на три» — «на» между единицей и числом.
        let numberIndex = words.indices.contains(index + 1) && words[index + 1] == "на" ? index + 2 : index + 1
        let following = number(at: numberIndex, in: words)
        let followedByUnit = following.map { words.indices.contains($0.range.upperBound + 1) && isUnit(words[$0.range.upperBound + 1]) } ?? false

        // «час двадцать» — один час и минуты.
        if singleHourWords.contains(unit) {
            if let following, !followedByUnit, following.value < 60 {
                return Duration(minutes: 60 + Int(following.value), range: index...following.range.upperBound)
            }
            return Duration(minutes: 60, range: index...index)
        }
        // «часа три», «минут сорок» — «примерно столько».
        if let following, !followedByUnit {
            return Duration(minutes: Int((following.value * perUnit).rounded()), range: index...following.range.upperBound)
        }
        return nil
    }

    private static func isClockTime(before index: Int, in words: [String]) -> Bool {
        index >= 1 && clockPrepositions.contains(words[index - 1])
    }

    /// «2 часа 15 минут» — часы и минуты рядом складываются.
    private static func merged(_ durations: [Duration]) -> [Duration] {
        var result: [Duration] = []
        for duration in durations {
            if let last = result.last, duration.range.lowerBound <= last.range.upperBound + 1,
               last.minutes >= 60, duration.minutes < 60 {
                result[result.count - 1] = Duration(minutes: last.minutes + duration.minutes,
                                                    range: last.range.lowerBound...duration.range.upperBound)
            } else {
                result.append(duration)
            }
        }
        return result
    }

    /// «работал», «поработал», «продуктивных часов пять» — про общий объём.
    static let workStems = ["работ", "поработ", "проработ", "отработ", "пахал", "трудил", "продуктив", "кодил", "программир", "сидел"]
    /// «всего», «итого», «в сумме» — про итог.
    static let totalWords: Set<String> = ["всего", "итого", "сумме", "целом", "общей"]

    // MARK: - Оценка дня и силы

    static let hardStems = [
        "тяжел", "тяжк", "устал", "вымота", "выжат", "измот", "замота", "задолба", "перегруз",
        "стресс", "аврал", "ужасн", "кошмар", "отвратит", "выгор", "разбит", "плох",
    ]
    static let greatStems = [
        "отличн", "прекрасн", "классн", "супер", "продуктивн", "кайф", "замечательн",
        "доволен", "довольн", "радостн", "бодр", "энергичн",
    ]
    static let greatWords: Set<String> = ["огонь", "легко", "круто", "здорово", "класс"]
    static let okStems = ["нормальн", "норм", "обычн", "ровн", "спокойн", "средн", "неплох"]
    static let softeners: Set<String> = ["немного", "чуть", "слегка", "немножко", "слегонца", "капельку"]
    static let hardPhrases: [[String]] = [["нет", "сил"], ["сил", "нет"], ["без", "сил"], ["не", "выспался"], ["не", "выспалась"]]

    static let lowEnergyStems = ["устал", "вымота", "выжат", "измот", "сонн", "разбит", "выгор"]
    static let highEnergyStems = ["бодр", "энергичн", "заряжен", "свеж"]
    static let lowEnergyPhrases: [[String]] = [["нет", "сил"], ["сил", "нет"], ["без", "сил"], ["не", "выспался"], ["не", "выспалась"]]
    static let highEnergyPhrases: [[String]] = [["полон", "сил"], ["полна", "сил"], ["много", "сил"], ["есть", "силы"]]

    /// Оценка дня по всему рассказу: «тяжело» против «продуктивно» с учётом
    /// «не» и смягчений («немного устал»).
    static func rating(_ words: [String]) -> DayRating? {
        var score = 0.0
        var sentiment = false

        for (index, word) in words.enumerated() {
            let weight = weightModifier(at: index, in: words)
            if hardStems.contains(where: { word.hasPrefix($0) }) {
                score += -1 * weight
                sentiment = true
            } else if greatWords.contains(word) || greatStems.contains(where: { word.hasPrefix($0) }) {
                score += 1 * weight
                sentiment = true
            } else if okStems.contains(where: { word.hasPrefix($0) }) {
                if word.hasPrefix("неплох") { score += 0.5 }
                sentiment = true
            }
        }
        if contains(words, anyOf: hardPhrases) {
            score -= 1
            sentiment = true
        }
        if contains(words, anyOf: [["так", "себе"]]) {
            score -= 0.5
            sentiment = true
        }
        guard sentiment else { return nil }
        if score <= -1 { return .hard }
        if score >= 1 { return .great }
        return .ok
    }

    static func energy(_ words: [String]) -> SelfReportedEnergy? {
        var score = 0.0
        var mentioned = false
        for (index, word) in words.enumerated() {
            let weight = weightModifier(at: index, in: words)
            if lowEnergyStems.contains(where: { word.hasPrefix($0) }) {
                score -= weight
                mentioned = true
            } else if highEnergyStems.contains(where: { word.hasPrefix($0) }) {
                score += weight
                mentioned = true
            }
        }
        if contains(words, anyOf: lowEnergyPhrases) {
            score -= 1
            mentioned = true
        }
        if contains(words, anyOf: highEnergyPhrases) {
            score += 1
            mentioned = true
        }
        guard mentioned else { return nil }
        if score <= -1 { return .low }
        if score >= 1 { return .high }
        return .medium
    }

    /// «не устал» переворачивает смысл, «немного устал» ослабляет.
    private static func weightModifier(at index: Int, in words: [String]) -> Double {
        let previous = index >= 1 ? words[index - 1] : ""
        let beforePrevious = index >= 2 ? words[index - 2] : ""
        if previous == "не" || (beforePrevious == "не" && previous == "очень") { return -0.5 }
        if softeners.contains(previous) || softeners.contains(beforePrevious) { return 0.5 }
        return 1
    }
}
