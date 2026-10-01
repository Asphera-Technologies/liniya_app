//
//  QuickTaskParser.swift
//  Linea
//
//  Быстрый ввод задачи одной строкой — набранной или надиктованной:
//  «Купить продукты завтра на полчаса, важно» → название «Купить продукты»,
//  день — завтра, полчаса, высокий приоритет. Без модели и без сети:
//  небольшие явные словари, как у разбора итога дня, каждое правило
//  закреплено тестом.
//
//  Распознанное вырезается из названия, поэтому правило одно: лучше не узнать
//  параметр, чем испортить название. Всё, что Linea поняла, человек сразу
//  видит в чипах под строкой и поправит одним нажатием.
//

import Foundation

/// Что Linea поняла из строки быстрого ввода.
nonisolated struct QuickTaskParse: Hashable, Sendable {
    nonisolated enum Part: String, Hashable, Sendable {
        /// «Добавь задачу», «надо» — служебное в начале фразы.
        case filler
        case day
        case deadline
        case startTime
        case duration
        case priority
        case goal
    }

    nonisolated struct Recognized: Hashable, Sendable {
        let part: Part
        /// Как было написано или надиктовано.
        let text: String
    }

    /// Название без распознанных параметров.
    var title: String
    var day: TaskDay?
    var deadline: Date?
    /// «в 15:00» — задача с фиксированным временем начала.
    var startTime: TimeOfDay?
    var minutes: Int?
    var priority: TaskPriority?
    var demand: CognitiveDemand?
    /// «для цели …» — цель названа явно и нашлась среди активных.
    var goalID: UUID?
    var recognized: [Recognized]

    init(
        title: String,
        day: TaskDay? = nil,
        deadline: Date? = nil,
        startTime: TimeOfDay? = nil,
        minutes: Int? = nil,
        priority: TaskPriority? = nil,
        demand: CognitiveDemand? = nil,
        goalID: UUID? = nil,
        recognized: [Recognized] = []
    ) {
        self.title = title
        self.day = day
        self.deadline = deadline
        self.startTime = startTime
        self.minutes = minutes
        self.priority = priority
        self.demand = demand
        self.goalID = goalID
        self.recognized = recognized
    }
}

nonisolated struct QuickTaskParser: Sendable {
    /// Длительность вне этих границ — не про задачу («на 3 недели»).
    static let minutesRange = 5...720

    init() {}

    func parse(_ text: String, goals: [LineaGoal] = [], profile: UserProfile = .default, time: TimeContext) -> QuickTaskParse {
        var state = QuickTaskParseState(text: text, profile: profile, time: time)
        state.stripFillers()
        state.matchPriority()
        state.matchDeadlines()
        state.matchDays()
        state.matchStartTimes()
        state.matchDurations()
        state.matchGoal(in: goals.filter { $0.isActive && !$0.isCompleted })
        state.detectDemand()
        return state.result()
    }
}

// MARK: - Словари

nonisolated enum QuickTaskWords {
    /// Календарь: 1 — воскресенье, 2 — понедельник, … 7 — суббота.
    static let weekdays: [String: Int] = [
        "понедельник": 2, "понедельника": 2, "понедельнику": 2,
        "вторник": 3, "вторника": 3, "вторнику": 3,
        "среда": 4, "среду": 4, "среды": 4, "среде": 4,
        "четверг": 5, "четверга": 5, "четвергу": 5,
        "пятница": 6, "пятницу": 6, "пятницы": 6, "пятнице": 6,
        "суббота": 7, "субботу": 7, "субботы": 7, "субботе": 7,
        "воскресенье": 1, "воскресенья": 1, "воскресенью": 1,
    ]
    /// «пн», «пт» — только после предлога: «в пт», «до пт».
    static let weekdayAbbreviations: [String: Int] = ["пн": 2, "вт": 3, "ср": 4, "чт": 5, "пт": 6, "сб": 7, "вс": 1]
    static let months: [String: Int] = [
        "января": 1, "февраля": 2, "марта": 3, "апреля": 4, "мая": 5, "июня": 6,
        "июля": 7, "августа": 8, "сентября": 9, "октября": 10, "ноября": 11, "декабря": 12,
        "янв": 1, "фев": 2, "мар": 3, "апр": 4, "июн": 6, "июл": 7, "авг": 8,
        "сен": 9, "сент": 9, "окт": 10, "ноя": 11, "нояб": 11, "дек": 12,
    ]
    static let thisWords: Set<String> = ["эту", "этот", "это", "этой", "этого", "ближайшую", "ближайший", "ближайшее", "ближайшей"]
    static let nextWords: Set<String> = ["следующую", "следующий", "следующее", "следующей", "следующего", "будущую", "будущий", "будущее", "будущей"]
    /// «в 7 вечера», «в 9 утра».
    static let dayParts: Set<String> = ["утра", "дня", "вечера", "ночи"]

    /// Приоритет словами. Длинные фразы раньше коротких: «не срочно» — не «срочно».
    static let priorityPhrases: [(words: [String], priority: TaskPriority, someday: Bool)] = [
        (["с", "высоким", "приоритетом"], .important, false),
        (["с", "низким", "приоритетом"], .low, false),
        (["со", "средним", "приоритетом"], .normal, false),
        (["когда", "будет", "время"], .low, true),
        (["если", "будет", "время"], .low, true),
        (["высоким", "приоритетом"], .important, false),
        (["низким", "приоритетом"], .low, false),
        (["средним", "приоритетом"], .normal, false),
        (["высокий", "приоритет"], .important, false),
        (["приоритет", "высокий"], .important, false),
        (["низкий", "приоритет"], .low, false),
        (["приоритет", "низкий"], .low, false),
        (["средний", "приоритет"], .normal, false),
        (["приоритет", "средний"], .normal, false),
        (["обычный", "приоритет"], .normal, false),
        (["приоритет", "обычный"], .normal, false),
        (["очень", "срочно"], .important, false),
        (["очень", "важно"], .important, false),
        (["не", "срочно"], .low, false),
        (["не", "важно"], .low, false),
        (["не", "горит"], .low, false),
        (["по", "возможности"], .low, false),
        (["если", "успею"], .low, false),
        (["важная", "задача"], .important, false),
        (["срочная", "задача"], .important, false),
        (["важное", "дело"], .important, false),
        (["срочное", "дело"], .important, false),
        (["срочно"], .important, false),
        (["важно"], .important, false),
        (["критично"], .important, false),
        (["приоритетно"], .important, false),
        (["горит"], .important, false),
        (["несрочно"], .low, false),
        (["неважно"], .low, false),
        (["когда-нибудь"], .low, true),
        (["как-нибудь"], .low, true),
    ]

    /// Служебное в начале надиктованной фразы.
    static let leadingFillers: Set<String> = ["ну", "пожалуйста", "надо", "нужно", "необходимо"]
    /// «Так, купить хлеб» — только с запятой: «Так держать» — уже название.
    static let pausedFillers: Set<String> = ["так", "итак", "слушай", "короче"]
    /// «Добавь задачу …», «Запиши мне …» — только вместе с дополнением,
    /// иначе «Записать видео» потеряло бы глагол.
    static let commandVerbs: Set<String> = ["добавь", "добавить", "создай", "создать", "запиши", "записать", "поставь", "занеси", "внеси"]
    static let commandObjects: Set<String> = ["задачу", "задача", "задачку", "дело", "напоминание"]

    /// Перед длительностью: «на полчаса», «примерно 40 минут», «за час».
    static let durationLeads: Set<String> = ["на", "за", "примерно", "около", "где-то", "приблизительно", "минимум", "максимум"]

    /// Не начинают и не заканчивают название: остаются, когда соседнее слово
    /// стало параметром («Отчёт и» после «… и завтра»).
    static let dangling: Set<String> = [
        "и", "а", "но", "или", "на", "в", "во", "к", "ко", "до", "для", "по", "с", "со",
        "за", "от", "у", "же", "то", "что", "чтобы",
    ]
}

// MARK: - Разбор

/// Состояние одного разбора: какие куски строки уже стали параметрами.
nonisolated private struct QuickTaskParseState {
    let text: String
    let profile: UserProfile
    let time: TimeContext
    let tokens: [CaptureToken]
    /// Слова для `CheckInText`, по индексам совпадают с `tokens`. У знаков,
    /// времени и дат — пустая строка: для словарей это не слова.
    let words: [String]
    var consumed: [Bool]
    var parse = QuickTaskParse(title: "")
    /// «до 18:00» без дня: день станет известен в конце разбора.
    var deadlineTime: TimeOfDay?

    init(text: String, profile: UserProfile, time: TimeContext) {
        self.text = text
        self.profile = profile
        self.time = time
        tokens = CaptureTokenizer.tokens(text)
        words = tokens.map(\.word)
        consumed = Array(repeating: false, count: tokens.count)
    }

    // MARK: Доступ к кускам

    /// Свободное слово (не число, не знак) или nil.
    func word(_ index: Int) -> String? {
        guard tokens.indices.contains(index), !consumed[index], tokens[index].kind == .word else { return nil }
        return tokens[index].word
    }

    func isFree(_ index: Int) -> Bool {
        tokens.indices.contains(index) && !consumed[index]
    }

    func matches(_ phrase: [String], at index: Int) -> Bool {
        phrase.indices.allSatisfy { word(index + $0) == phrase[$0] }
    }

    /// Целое число цифрами или словами («пятнадцать») с этого места.
    func integer(at index: Int, in range: ClosedRange<Int>) -> (value: Int, last: Int)? {
        guard isFree(index), let found = CheckInText.number(at: index, in: words) else { return nil }
        guard found.range.allSatisfy(isFree) else { return nil }
        guard found.value == found.value.rounded(), found.value >= Double(range.lowerBound),
              found.value <= Double(range.upperBound) else { return nil }
        return (Int(found.value), found.range.upperBound)
    }

    /// После этого места фраза кончается: конец строки, знак или уже
    /// распознанный параметр.
    func isBoundary(_ index: Int) -> Bool {
        guard tokens.indices.contains(index), !consumed[index] else { return true }
        switch tokens[index].kind {
        case .pause, .end, .mark: return true
        default: return false
        }
    }

    mutating func consume(_ range: ClosedRange<Int>, as part: QuickTaskParse.Part) {
        for index in range { consumed[index] = true }
        let start = tokens[range.lowerBound].range.lowerBound
        let end = tokens[range.upperBound].range.upperBound
        parse.recognized.append(QuickTaskParse.Recognized(part: part, text: String(text[start..<end])))
    }

    // MARK: Служебное в начале

    mutating func stripFillers() {
        var index = 0
        while true {
            guard let first = word(index), hasText(after: index) else { return }
            var last: Int?
            if QuickTaskWords.leadingFillers.contains(first) {
                last = index
            } else if QuickTaskWords.pausedFillers.contains(first), tokens.indices.contains(index + 1),
                      tokens[index + 1].kind == .pause {
                last = index
            } else if first == "мне", let next = word(index + 1), next == "надо" || next == "нужно" {
                last = index + 1
            } else if QuickTaskWords.commandVerbs.contains(first) {
                var end = index
                if word(end + 1) == "мне" { end += 1 }
                if let object = word(end + 1), QuickTaskWords.commandObjects.contains(object) { end += 1 }
                if end > index { last = end }
            } else if first == "новая", word(index + 1) == "задача" {
                last = index + 1
            } else if first == "задача" || first == "задачу" {
                last = index
            } else if first == "напомни" || first == "напомнить" {
                last = word(index + 1) == "мне" ? index + 1 : index
            }
            guard let last, hasText(after: last) else { return }
            consume(index...last, as: .filler)
            index = last + 1
            // «Задача: купить хлеб»
            while tokens.indices.contains(index), tokens[index].kind == .pause {
                index += 1
            }
        }
    }

    private func hasText(after index: Int) -> Bool {
        tokens.indices.contains { $0 > index && tokens[$0].isText }
    }

    // MARK: Приоритет

    mutating func matchPriority() {
        for index in tokens.indices where isFree(index) {
            guard parse.priority == nil else { break }
            if let phrase = QuickTaskWords.priorityPhrases.first(where: { matches($0.words, at: index) }) {
                consume(index...(index + phrase.words.count - 1), as: .priority)
                parse.priority = phrase.priority
                if phrase.someday { parse.day = .someday }
            }
        }
        // «!!» и больше — высокий; одиночный «!» — просто знак.
        var index = 0
        while index < tokens.count, parse.priority == nil {
            var end = index
            while end < tokens.count, tokens[end].kind == .mark, !consumed[end] { end += 1 }
            if end - index >= 2 {
                consume(index...(end - 1), as: .priority)
                parse.priority = .important
            }
            index = max(end, index + 1)
        }
    }

    // MARK: Срок

    mutating func matchDeadlines() {
        for index in tokens.indices where isFree(index) {
            guard parse.deadline == nil, deadlineTime == nil else { return }
            guard let first = word(index) else { continue }
            var start = index
            var next = index + 1
            if first == "до" || first == "к" || first == "ко" {
                // «до 18:00», «к пятнице»
            } else if first == "дедлайн" || first == "срок" {
                if first == "срок", word(index - 1) == "крайний" { start = index - 1 }
                while tokens.indices.contains(next), tokens[next].kind == .pause { next += 1 }
                if let preposition = word(next), ["до", "к", "ко", "на"].contains(preposition) { next += 1 }
            } else {
                continue
            }
            if let part = applyDeadline(at: next) { consume(start...lastDeadlineIndex, as: part) }
        }
    }

    /// Где кончилось последнее выражение срока — его выставляет `applyDeadline`.
    private var lastDeadlineIndex = 0

    /// Срок с этого места: день, время, «вечера», «конца недели». Возвращает,
    /// чем оказалось выражение: «до конца недели» — это день «на неделе».
    private mutating func applyDeadline(at index: Int) -> QuickTaskParse.Part? {
        if let (day, last) = dayExpression(at: index, allowAbbreviation: true) {
            var at = profile.workdayEnd
            var end = last
            // «до пятницы 18:00», «к пятнице к 15:00»
            var timeIndex = last + 1
            if let preposition = word(timeIndex), ["в", "до", "к"].contains(preposition) { timeIndex += 1 }
            if let (moment, momentLast) = clock(at: timeIndex, allowNumber: true, bare: true) {
                at = moment
                end = momentLast
            }
            parse.deadline = time.date(on: day, at: at)
            lastDeadlineIndex = end
            return .deadline
        }
        if let (moment, last) = clock(at: index, allowNumber: true, bare: true) {
            deadlineTime = moment
            lastDeadlineIndex = last
            return .deadline
        }
        guard let keyword = word(index) else { return nil }
        var part = QuickTaskParse.Part.deadline
        switch keyword {
        case "вечера", "вечеру":
            deadlineTime = TimeOfDay(hour: 18)
        case "обеда", "обеду":
            deadlineTime = TimeOfDay(hour: 13)
        case "утра", "утру":
            deadlineTime = TimeOfDay(hour: 10)
        case "конца", "концу":
            switch word(index + 1) {
            case "дня":
                deadlineTime = profile.workdayEnd
            case "недели":
                // «до конца недели» — то же, что «на неделе».
                guard parse.day == nil else { return nil }
                parse.day = .thisWeek
                part = .day
            case "месяца":
                parse.deadline = endOfMonth()
            default:
                return nil
            }
            lastDeadlineIndex = index + 1
            return part
        default:
            return nil
        }
        lastDeadlineIndex = index
        return part
    }

    private func endOfMonth() -> Date {
        let calendar = time.calendar
        let start = calendar.dateInterval(of: .month, for: time.today)?.end ?? time.adding(days: 30, to: time.today)
        return time.date(on: time.adding(days: -1, to: start), at: profile.workdayEnd)
    }

    // MARK: День

    mutating func matchDays() {
        for index in tokens.indices where isFree(index) {
            guard parse.day == nil else { return }
            guard let first = word(index) else {
                // «15.10», «15 октября» без предлога.
                if let (day, last) = dayExpression(at: index, allowAbbreviation: false) {
                    consume(index...last, as: .day)
                    parse.day = taskDay(for: day)
                }
                continue
            }
            if first == "на" || first == "в" || first == "во" {
                if let (day, last) = dayAfterPreposition(first, at: index + 1) {
                    consume(index...last, as: .day)
                    parse.day = day
                }
                continue
            }
            if first == "через", let (day, last) = dayAfterThrough(at: index + 1) {
                consume(index...last, as: .day)
                parse.day = day
                continue
            }
            if let (day, last) = dayExpression(at: index, allowAbbreviation: false) {
                consume(index...last, as: .day)
                parse.day = taskDay(for: day)
            }
        }
    }

    /// «на завтра», «на неделе», «на следующей неделе», «на выходных»,
    /// «в пятницу», «в выходные», «в течение недели».
    private func dayAfterPreposition(_ preposition: String, at index: Int) -> (TaskDay, Int)? {
        guard let next = word(index) else {
            if preposition == "на", let (day, last) = dayExpression(at: index, allowAbbreviation: false) {
                return (taskDay(for: day), last)
            }
            return nil
        }
        if preposition == "на" {
            if next == "неделе" { return (.thisWeek, index) }
            if QuickTaskWords.thisWords.contains(next), word(index + 1) == "неделе" { return (.thisWeek, index + 1) }
            if QuickTaskWords.nextWords.contains(next), word(index + 1) == "неделе" {
                return (.date(TaskDay.nextMonday(time: time)), index + 1)
            }
            if next == "выходных" || next == "выходные" { return (taskDay(for: weekend()), index) }
        } else {
            if next == "выходные" { return (taskDay(for: weekend()), index) }
            if (next == "эти" || next == "ближайшие"), word(index + 1) == "выходные" { return (taskDay(for: weekend()), index + 1) }
            if next == "течение", word(index + 1) == "недели" { return (.thisWeek, index + 1) }
        }
        if let (day, last) = dayExpression(at: index, allowAbbreviation: preposition != "на") {
            return (taskDay(for: day), last)
        }
        return nil
    }

    /// «через 3 дня», «через неделю», «через месяц».
    private func dayAfterThrough(at index: Int) -> (TaskDay, Int)? {
        var amount = 1
        var unitIndex = index
        if let (value, last) = integer(at: index, in: 1...365) {
            amount = value
            unitIndex = last + 1
        }
        guard let unit = word(unitIndex) else { return nil }
        let days: Int
        switch unit {
        case "день" where unitIndex != index, "дня", "дней":
            days = amount
        case "неделю", "недели", "недель":
            days = amount * 7
        case "месяц", "месяца", "месяцев":
            let date = time.calendar.date(byAdding: .month, value: amount, to: time.today) ?? time.adding(days: 30 * amount, to: time.today)
            return (taskDay(for: time.startOfDay(date)), unitIndex)
        default:
            return nil
        }
        return (taskDay(for: time.adding(days: days, to: time.today)), unitIndex)
    }

    /// Конкретный день: «сегодня», «завтра», «пятницу», «следующий вторник»,
    /// «15 октября», «25 числа», «15.10».
    func dayExpression(at index: Int, allowAbbreviation: Bool) -> (Date, Int)? {
        guard isFree(index) else { return nil }
        if case .date(let day, let month, let year) = tokens[index].kind {
            return date(day: day, month: month, year: year).map { ($0, index) }
        }
        guard let first = word(index) else {
            // «15 октября», «25 числа»
            guard let (day, last) = integer(at: index, in: 1...31), let monthWord = word(last + 1) else { return nil }
            if let month = QuickTaskWords.months[monthWord] {
                return date(day: day, month: month, year: nil).map { ($0, last + 1) }
            }
            if monthWord == "числа" {
                return dayOfThisMonth(day).map { ($0, last + 1) }
            }
            return nil
        }
        switch first {
        case "сегодня":
            return (time.today, index)
        case "завтра":
            return (time.adding(days: 1, to: time.today), index)
        case "послезавтра":
            return (time.adding(days: 2, to: time.today), index)
        default:
            break
        }
        var weekdayIndex = index
        var isThis = false
        var isNext = false
        if QuickTaskWords.thisWords.contains(first) {
            isThis = true
            weekdayIndex += 1
        } else if QuickTaskWords.nextWords.contains(first) {
            isNext = true
            weekdayIndex += 1
        }
        guard let name = word(weekdayIndex) else { return nil }
        let weekday = QuickTaskWords.weekdays[name] ?? (allowAbbreviation ? QuickTaskWords.weekdayAbbreviations[name] : nil)
        guard let weekday else { return nil }
        return (weekdayDate(weekday, isThis: isThis, isNext: isNext), weekdayIndex)
    }

    /// Ближайший такой день недели после сегодняшнего; «эта среда» в среду —
    /// сегодня, «следующая пятница» — пятница следующей недели.
    private func weekdayDate(_ weekday: Int, isThis: Bool, isNext: Bool) -> Date {
        if isNext {
            return time.adding(days: (weekday + 5) % 7, to: TaskDay.nextMonday(time: time))
        }
        let current = time.calendar.component(.weekday, from: time.today)
        var ahead = (weekday - current + 7) % 7
        if ahead == 0, !isThis { ahead = 7 }
        return time.adding(days: ahead, to: time.today)
    }

    /// Ближайшая суббота; в выходные — сегодня.
    private func weekend() -> Date {
        let current = time.calendar.component(.weekday, from: time.today)
        if current == 7 || current == 1 { return time.today }
        return time.adding(days: 7 - current, to: time.today)
    }

    /// День и месяц без года — ближайший такой день, сегодня или позже.
    private func date(day: Int, month: Int, year: Int?) -> Date? {
        let calendar = time.calendar
        let currentYear = calendar.component(.year, from: time.today)
        for candidateYear in [year ?? currentYear, currentYear + 1] {
            var components = DateComponents()
            components.year = candidateYear
            components.month = month
            components.day = day
            guard let date = calendar.date(from: components),
                  calendar.component(.day, from: date) == day else { return nil }
            let start = time.startOfDay(date)
            if year != nil || start >= time.today { return start }
        }
        return nil
    }

    /// «25 числа» — этого месяца, а если уже прошло — следующего.
    private func dayOfThisMonth(_ day: Int) -> Date? {
        let calendar = time.calendar
        for offset in 0...1 {
            guard let month = calendar.date(byAdding: .month, value: offset, to: time.today) else { continue }
            var components = calendar.dateComponents([.year, .month], from: month)
            components.day = day
            guard let date = calendar.date(from: components), calendar.component(.day, from: date) == day else { continue }
            let start = time.startOfDay(date)
            if start >= time.today { return start }
        }
        return nil
    }

    private func taskDay(for date: Date) -> TaskDay {
        let day = time.startOfDay(date)
        if day == time.today { return .today }
        if day == time.adding(days: 1, to: time.today) { return .tomorrow }
        return .date(day)
    }

    // MARK: Время начала

    mutating func matchStartTimes() {
        for index in tokens.indices where isFree(index) {
            guard parse.startTime == nil else { return }
            if let first = word(index), first == "в" || first == "во" || first == "на" {
                // «на 2 часа» — длительность, поэтому после «на» только «15:00».
                if let (value, last) = clock(at: index + 1, allowNumber: first != "на", bare: true) {
                    consume(index...last, as: .startTime)
                    parse.startTime = value
                }
            } else if case .clock(let value) = tokens[index].kind {
                consume(index...index, as: .startTime)
                parse.startTime = value
            }
        }
    }

    /// Время на часах: «15:00», «полдень», «3 часа дня», «7 вечера», «15
    /// часов». Голое число («в 15») — только если `bare` и дальше конец фразы.
    func clock(at index: Int, allowNumber: Bool, bare: Bool) -> (TimeOfDay, Int)? {
        guard isFree(index) else { return nil }
        if case .clock(let value) = tokens[index].kind { return (value, index) }
        if let first = word(index), first == "полдень" || first == "полудня" { return (TimeOfDay(hour: 12), index) }
        guard allowNumber, let (number, numberLast) = integer(at: index, in: 0...23) else { return nil }
        var hour = number
        var last = numberLast
        var hasUnit = false
        if let unit = word(last + 1), CheckInText.hourWords.contains(unit) {
            hasUnit = true
            last += 1
        }
        var part: String?
        if let next = word(last + 1), QuickTaskWords.dayParts.contains(next) {
            part = next
            last += 1
        }
        if part == nil, !hasUnit {
            guard bare, isBoundary(last + 1) else { return nil }
        }
        switch part {
        case "утра", "ночи":
            if hour == 12 { hour = 0 }
        case "дня", "вечера":
            if hour < 12 { hour += 12 }
        default:
            // «в 7» в рабочий день скорее вечер, чем утро: до начала рабочего
            // дня — значит, после обеда.
            if hour > 0, hour < profile.workdayStart.hour, hour + 12 <= 23 { hour += 12 }
        }
        return (TimeOfDay(hour: hour), last)
    }

    // MARK: Длительность

    mutating func matchDurations() {
        // «около часа», «примерно часа два» — «часа» без числа CheckInText не берёт.
        for index in tokens.indices where isFree(index) {
            guard parse.minutes == nil else { return }
            if word(index) == "часа", let lead = word(index - 1), lead == "около" || lead == "примерно" || lead == "почти",
               CheckInText.number(at: index + 1, in: words) == nil {
                consume((index - 1)...index, as: .duration)
                parse.minutes = 60
            }
        }
        for duration in CheckInText.durations(in: words) {
            guard parse.minutes == nil else { return }
            guard QuickTaskParser.minutesRange.contains(duration.minutes) else { continue }
            guard duration.range.allSatisfy(isFree) else { continue }
            var start = duration.range.lowerBound
            // «через 2 часа» — это когда начать, а не сколько займёт.
            if word(start - 1) == "через" { continue }
            if word(start - 1) == "течение", word(start - 2) == "в" {
                start -= 2
            } else {
                while let lead = word(start - 1), QuickTaskWords.durationLeads.contains(lead) { start -= 1 }
            }
            consume(start...duration.range.upperBound, as: .duration)
            parse.minutes = duration.minutes
        }
    }

    // MARK: Цель

    /// «для цели Запустить MVP», «к цели …», «по цели …», «цель: …». Имя
    /// цели — до конца фразы или до следующего параметра. Не нашлась среди
    /// активных — слова остаются в названии.
    mutating func matchGoal(in goals: [LineaGoal]) {
        guard !goals.isEmpty else { return }
        for index in tokens.indices where isFree(index) {
            guard let first = word(index) else { continue }
            var nameStart: Int
            if ["для", "к", "ко", "по", "в"].contains(first), let next = word(index + 1), next == "цели" || next == "цель" {
                nameStart = index + 2
            } else if first == "цель", tokens.indices.contains(index + 1), tokens[index + 1].kind == .pause {
                // «Цель: MVP». Без двоеточия «цель» — часть названия: «Поставить цель на год».
                nameStart = index + 1
            } else {
                continue
            }
            while tokens.indices.contains(nameStart), tokens[nameStart].kind == .pause { nameStart += 1 }
            var nameEnd = nameStart - 1
            while isFree(nameEnd + 1), tokens[nameEnd + 1].isText { nameEnd += 1 }
            guard nameEnd >= nameStart else { continue }
            let name = String(text[tokens[nameStart].range.lowerBound..<tokens[nameEnd].range.upperBound])
            guard let goal = Self.goal(named: name, in: goals) else { continue }
            consume(index...nameEnd, as: .goal)
            parse.goalID = goal.id
            return
        }
    }

    /// Цель, на которую похоже сказанное: хотя бы половина значимых слов
    /// названа так же, как в цели. «Запустить линию» найдёт «Запустить MVP
    /// Linea», хотя «Linea» распознаётся по-русски.
    static func goal(named name: String, in goals: [LineaGoal]) -> LineaGoal? {
        let said = RussianWords.stems(name)
        guard !said.isEmpty else { return nil }
        let scored = goals.compactMap { goal -> (goal: LineaGoal, coverage: Double, similarity: Double)? in
            let stems = RussianWords.stems(goal.title)
            let common = said.intersection(stems).count
            guard common > 0 else { return nil }
            let coverage = Double(common) / Double(said.count)
            guard coverage >= 0.5 else { return nil }
            return (goal, coverage, RussianWords.similarity(name, goal.title))
        }
        return scored.max { lhs, rhs in
            if lhs.coverage != rhs.coverage { return lhs.coverage < rhs.coverage }
            if lhs.similarity != rhs.similarity { return lhs.similarity < rhs.similarity }
            return lhs.goal.id.uuidString > rhs.goal.id.uuidString
        }?.goal
    }

    // MARK: Сложность

    /// «сложная», «быстро» — подсказка о сложности. Слова остаются в
    /// названии: «Сложная презентация» без «сложная» потеряла бы смысл.
    mutating func detectDemand() {
        for token in tokens where token.kind == .word {
            if token.word.hasPrefix("сложн") {
                parse.demand = .deep
                return
            }
            if token.word.hasPrefix("легк") || token.word.hasPrefix("быстр") || token.word == "мелочь" {
                parse.demand = .light
                return
            }
        }
    }

    // MARK: Итог

    func result() -> QuickTaskParse {
        var parse = self.parse
        if let deadlineTime {
            // «до 18:00» — в день задачи, а без дня — сегодня или завтра, если уже поздно.
            let base: Date
            var isExplicitDay = true
            switch parse.day {
            case .today?: base = time.today
            case .tomorrow?: base = time.adding(days: 1, to: time.today)
            case .date(let day)?: base = day
            default:
                base = time.today
                isExplicitDay = false
            }
            var moment = time.date(on: base, at: deadlineTime)
            if !isExplicitDay, moment <= time.now { moment = time.date(on: time.adding(days: 1, to: base), at: deadlineTime) }
            parse.deadline = moment
        }
        let title = assembledTitle()
        parse.title = title.isEmpty ? Self.cleaned(text) : title
        return parse
    }

    /// Название из того, что не стало параметром. Между соседними словами —
    /// исходные знаки и пробелы, на месте вырезанного — пробел.
    private func assembledTitle() -> String {
        var kept = tokens.indices.filter { !consumed[$0] && tokens[$0].isText }[...]
        while let first = kept.first, QuickTaskWords.dangling.contains(tokens[first].word) { kept = kept.dropFirst() }
        while let last = kept.last, QuickTaskWords.dangling.contains(tokens[last].word) { kept = kept.dropLast() }

        var title = ""
        var previous: Int?
        for index in kept {
            if let previous {
                let between = (previous + 1)..<index
                if between.allSatisfy({ !consumed[$0] }) {
                    title += text[tokens[previous].range.upperBound..<tokens[index].range.lowerBound]
                } else {
                    title += " "
                }
            }
            title += text[tokens[index].range]
            previous = index
        }
        return Self.cleaned(title)
    }

    /// Пробелы и переводы строк — одним пробелом, первая буква заглавная.
    static func cleaned(_ text: String) -> String {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return RussianWords.capitalizedFirst(collapsed)
    }
}
