//
//  GoalLineParser.swift
//  Linea
//
//  Быстрая цель — одна строка, как быстрая задача: «Выпустить Линия в
//  TestFlight до 15-го октября» → название «Выпустить Линия в TestFlight» и
//  срок — 15 октября. Разбирает тот же `QuickTaskParser`, но в режиме цели:
//  только срок и важность. Длительности и времени начала у цели нет —
//  «Пробежать марафон за 4 часа» остаётся названием целиком.
//
//  Сроки у цели длиннее, чем у задачи, и говорят о них иначе: «до конца
//  года», «в декабре», «к лету», «за 3 месяца», «через полгода», «в 2027
//  году». Правила те же, что у задачи (ADR-031): у срока есть опора в
//  словах, два срока на выбор («в ноябре или в декабре») — ни одного, слова
//  остаются в названии.
//

import Foundation

/// Строка цели так, как Linea её поняла.
nonisolated struct GoalLineParse: Hashable, Sendable {
    /// Название без срока, важности и служебного («хочу», «цель:»).
    var title: String
    /// Срок цели — день. nil — срок не назван.
    var deadline: Date?
    /// Важность, если её сказали: «важно», «главная цель», «когда-нибудь».
    var priority: TaskPriority?
    var recognized: [QuickTaskParse.Recognized]
    /// Linea что-то поняла из слов и вырезала это из названия.
    var isUnderstood: Bool
}

nonisolated enum GoalLineParser {
    static func parse(
        _ text: String,
        profile: UserProfile = .default,
        time: TimeContext,
        parser: QuickTaskParser = QuickTaskParser()
    ) -> GoalLineParse {
        let parsed = parser.parseGoal(text, profile: profile, time: time).grounded(in: text)
        var deadline = parsed.deadline
        if deadline == nil, let day = parsed.day {
            switch day {
            case .someday: deadline = nil
            case .thisWeek: deadline = TaskDay.endOfWeek(time: time, profile: profile)
            case .today, .tomorrow, .date: deadline = day.resolve(time: time, profile: profile).date
            }
        }
        let title = RuleBasedGoalAnalyzer.title(parsed.title)
        return GoalLineParse(
            title: title,
            deadline: deadline.map(time.startOfDay),
            priority: parsed.priority,
            recognized: parsed.recognized,
            isUnderstood: !parsed.recognized.isEmpty && title != QuickTaskParser.cleaned(text)
        )
    }
}

// MARK: - Словари

nonisolated enum GoalLineWords {
    /// «Хочу», «моя цель —» в начале строки цели. Длинные — раньше коротких.
    static let fillers: [[String]] = [
        ["мне", "хочется"], ["хотелось", "бы"], ["я", "хочу"], ["мы", "хотим"], ["нам", "нужно"], ["нам", "надо"],
        ["моя", "цель"], ["наша", "цель"], ["новая", "цель"], ["я", "планирую"], ["мы", "планируем"],
        ["хочу"], ["хотим"], ["хочется"], ["цель"], ["планирую"], ["планируем"], ["собираюсь"], ["собираемся"],
    ]

    /// «Главная цель» — высокая важность.
    static let importantPhrases: [[String]] = [
        ["моя", "главная", "цель"], ["наша", "главная", "цель"], ["моя", "самая", "важная", "цель"],
        ["самая", "важная", "цель"], ["главная", "цель"], ["важная", "цель"], ["приоритетная", "цель"],
        ["цель", "номер", "один"],
    ]

    static let monthsGenitive: [String: Int] = [
        "января": 1, "февраля": 2, "марта": 3, "апреля": 4, "мая": 5, "июня": 6,
        "июля": 7, "августа": 8, "сентября": 9, "октября": 10, "ноября": 11, "декабря": 12,
    ]
    /// «в декабре».
    static let monthsPrepositional: [String: Int] = [
        "январе": 1, "феврале": 2, "марте": 3, "апреле": 4, "мае": 5, "июне": 6,
        "июле": 7, "августе": 8, "сентябре": 9, "октябре": 10, "ноябре": 11, "декабре": 12,
    ]
    /// «к декабрю».
    static let monthsDative: [String: Int] = [
        "январю": 1, "февралю": 2, "марту": 3, "апрелю": 4, "маю": 5, "июню": 6,
        "июлю": 7, "августу": 8, "сентябрю": 9, "октябрю": 10, "ноябрю": 11, "декабрю": 12,
    ]
    /// Сезоны — первым месяцем: «к лету» — к 1 июня.
    static let seasons: [String: Int] = [
        "весна": 3, "весны": 3, "весне": 3,
        "лето": 6, "лета": 6, "лету": 6,
        "осень": 9, "осени": 9,
        "зима": 12, "зимы": 12, "зиме": 12,
    ]
    static let thisWords: Set<String> = ["этого", "этому", "этом", "текущего", "текущему", "текущем"]
    static let nextWords: Set<String> = ["следующего", "следующему", "следующем", "будущего", "будущему", "будущем"]

    /// Слово срока цели — для «или»: «в ноябре или в декабре» — два на выбор.
    static func isPeriodWord(_ word: String) -> Bool {
        monthsPrepositional[word] != nil || monthsDative[word] != nil || seasons[word] != nil
    }
}

// MARK: - Правила строки цели

nonisolated extension QuickTaskParseState {

    /// Первый кусок, который ещё никто не забрал.
    private func firstFree() -> Int {
        var index = 0
        while tokens.indices.contains(index), consumed[index] || tokens[index].kind == .pause { index += 1 }
        return index
    }

    private func hasWords(after index: Int) -> Bool {
        tokens.indices.contains { $0 > index && !consumed[$0] && tokens[$0].isText }
    }

    /// «Хочу», «мы хотим», «моя цель —», «цель:» в начале — служебное.
    /// «Цель» одна во всей строке — это и есть название.
    mutating func stripGoalFillers() {
        var index = firstFree()
        while let phrase = GoalLineWords.fillers.first(where: { matches($0, at: index) }) {
            let last = index + phrase.count - 1
            guard hasWords(after: last) else { return }
            consume(index...last, as: .filler)
            index = last + 1
            while tokens.indices.contains(index), tokens[index].kind == .pause { index += 1 }
        }
    }

    /// «Главная цель», «самая важная цель» — высокая важность.
    mutating func matchGoalPriority() {
        for index in tokens.indices where isFree(index) {
            guard parse.priority == nil else { return }
            guard let phrase = GoalLineWords.importantPhrases.first(where: { matches($0, at: index) }) else { continue }
            let last = index + phrase.count - 1
            guard hasWords(after: last) || index > 0 else { continue }
            consume(index...last, as: .priority)
            parse.priority = .important
        }
    }

    /// Сроки масштаба цели: «до конца года», «в декабре», «к лету», «за 3
    /// месяца», «через полгода», «в 2027 году», «к Новому году».
    mutating func matchGoalHorizons() {
        for index in tokens.indices where isFree(index) {
            guard parse.deadline == nil else { return }
            guard let first = word(index), let (day, last) = horizon(startingWith: first, at: index) else { continue }
            guard accept(index...last, as: .deadline) else { continue }
            consume(index...last, as: .deadline)
            parse.deadline = time.date(on: day, at: profile.workdayEnd)
        }
    }

    /// День срока и где кончилось выражение.
    private func horizon(startingWith first: String, at index: Int) -> (Date, Int)? {
        switch first {
        case "до", "к", "ко":
            return endOfPeriod(at: index + 1) ?? startOfPeriod(after: first, at: index + 1)
        case "в", "во":
            return periodIn(at: index + 1)
        case "за":
            return span(at: index + 1, units: Self.spanUnits)
        case "через":
            // Дни, недели и месяцы «через» понимает разбор задачи; здесь — годы.
            return span(at: index + 1, units: ["год": .year, "года": .year, "лет": .year, "полгода": .halfYear])
        default:
            return nil
        }
    }

    // MARK: «до конца года»

    /// «конца года», «концу следующего месяца», «конца лета», «конца октября».
    private func endOfPeriod(at index: Int) -> (Date, Int)? {
        guard let end = word(index), end == "конца" || end == "концу" else { return nil }
        var next = index + 1
        var shift = 0
        if let modifier = word(next), GoalLineWords.thisWords.contains(modifier) || GoalLineWords.nextWords.contains(modifier) {
            shift = GoalLineWords.nextWords.contains(modifier) ? 1 : 0
            next += 1
        }
        guard let period = word(next) else { return nil }
        let today = time.today
        let calendar = time.calendar
        let year = calendar.component(.year, from: today)
        let month = calendar.component(.month, from: today)
        switch period {
        case "года", "году":
            return (lastDay(month: 12, year: year + shift), next)
        case "месяца", "месяцу":
            let target = month + shift
            return (lastDay(month: (target - 1) % 12 + 1, year: year + (target - 1) / 12), next)
        case "квартала", "кварталу":
            let quarterEnd = ((month - 1) / 3 + 1 + shift) * 3
            return (lastDay(month: (quarterEnd - 1) % 12 + 1, year: year + (quarterEnd - 1) / 12), next)
        default:
            if let first = GoalLineWords.seasons[period], shift == 0 {
                return (seasonEnd(firstMonth: first), next)
            }
            if let named = GoalLineWords.monthsGenitive[period], shift == 0 {
                return (upcomingMonthEnd(named), next)
            }
            return nil
        }
    }

    // MARK: «к декабрю», «к лету», «к Новому году», «к 2027 году»

    private func startOfPeriod(after preposition: String, at index: Int) -> (Date, Int)? {
        guard tokens.indices.contains(index) else { return nil }
        let calendar = time.calendar
        let year = calendar.component(.year, from: time.today)
        if let (value, last) = integer(at: index, in: 2000...2100), let unit = word(last + 1), unit == "году" || unit == "года" {
            // «к 2027 году», «до 2027 года» — до конца предыдущего.
            guard value > year else { return nil }
            return (lastDay(month: 12, year: value - 1), last + 1)
        }
        guard let next = word(index) else { return nil }
        if next == "новому" || next == "нового", let unit = word(index + 1), unit == "году" || unit == "года" {
            return (lastDay(month: 12, year: year), index + 1)
        }
        // «к декабрю»; «до декабря» — только сразу после «до»: «до 15
        // декабря» — это день, его понимает разбор задачи.
        if let month = GoalLineWords.monthsDative[next] ?? (preposition == "до" ? GoalLineWords.monthsGenitive[next] : nil) {
            return (upcomingMonthStart(month), index)
        }
        if let first = GoalLineWords.seasons[next] {
            return (upcomingMonthStart(first), index)
        }
        return nil
    }

    // MARK: «в декабре», «в этом году», «в 2027 году»

    private func periodIn(at index: Int) -> (Date, Int)? {
        guard tokens.indices.contains(index) else { return nil }
        let calendar = time.calendar
        let today = time.today
        let year = calendar.component(.year, from: today)
        let month = calendar.component(.month, from: today)
        if let (value, last) = integer(at: index, in: 2000...2100), let unit = word(last + 1), unit == "году" {
            guard value >= year else { return nil }
            return (lastDay(month: 12, year: value), last + 1)
        }
        guard let next = word(index) else { return nil }
        if let named = GoalLineWords.monthsPrepositional[next] {
            // «в декабре 2027 года» — год сказан.
            if let (value, last) = integer(at: index + 1, in: 2000...2100) {
                let end = word(last + 1) == "года" ? last + 1 : last
                guard value >= year else { return nil }
                return (lastDay(month: named, year: value), end)
            }
            return (upcomingMonthEnd(named), index)
        }
        guard GoalLineWords.thisWords.contains(next) || GoalLineWords.nextWords.contains(next),
              let period = word(index + 1) else { return nil }
        let shift = GoalLineWords.nextWords.contains(next) ? 1 : 0
        switch period {
        case "году":
            return (lastDay(month: 12, year: year + shift), index + 1)
        case "месяце":
            let target = month + shift
            return (lastDay(month: (target - 1) % 12 + 1, year: year + (target - 1) / 12), index + 1)
        case "квартале":
            let quarterEnd = ((month - 1) / 3 + 1 + shift) * 3
            return (lastDay(month: (quarterEnd - 1) % 12 + 1, year: year + (quarterEnd - 1) / 12), index + 1)
        default:
            return nil
        }
    }

    // MARK: «за 3 месяца», «через полгода»

    nonisolated enum SpanUnit { case day, week, month, halfYear, year }

    static let spanUnits: [String: SpanUnit] = [
        "день": .day, "дня": .day, "дней": .day,
        "неделю": .week, "недели": .week, "недель": .week,
        "месяц": .month, "месяца": .month, "месяцев": .month,
        "полгода": .halfYear,
        "год": .year, "года": .year, "лет": .year,
    ]

    private func span(at index: Int, units: [String: SpanUnit]) -> (Date, Int)? {
        var amount = 1
        var unitIndex = index
        if let (value, last) = integer(at: index, in: 1...100) {
            amount = value
            unitIndex = last + 1
        }
        guard let word = word(unitIndex), let unit = units[word] else { return nil }
        // «за день» без числа — не срок цели, а «за день до …».
        if unit == .day, unitIndex == index { return nil }
        let calendar = time.calendar
        let today = time.today
        let date: Date?
        switch unit {
        case .day: date = calendar.date(byAdding: .day, value: amount, to: today)
        case .week: date = calendar.date(byAdding: .day, value: 7 * amount, to: today)
        case .month: date = calendar.date(byAdding: .month, value: amount, to: today)
        case .halfYear: date = calendar.date(byAdding: .month, value: 6 * amount, to: today)
        case .year: date = calendar.date(byAdding: .year, value: amount, to: today)
        }
        return date.map { (time.startOfDay($0), unitIndex) }
    }

    // MARK: Календарь

    /// Последний день месяца.
    private func lastDay(month: Int, year: Int) -> Date {
        let calendar = time.calendar
        var components = DateComponents()
        components.year = month == 12 ? year + 1 : year
        components.month = month == 12 ? 1 : month + 1
        components.day = 1
        guard let next = calendar.date(from: components) else { return time.today }
        return time.adding(days: -1, to: time.startOfDay(next))
    }

    /// 1-е число ближайшего такого месяца — в будущем.
    private func upcomingMonthStart(_ month: Int) -> Date {
        let calendar = time.calendar
        let year = calendar.component(.year, from: time.today)
        for candidate in [year, year + 1] {
            var components = DateComponents()
            components.year = candidate
            components.month = month
            components.day = 1
            if let date = calendar.date(from: components), time.startOfDay(date) > time.today {
                return time.startOfDay(date)
            }
        }
        return time.today
    }

    /// Конец ближайшего такого месяца: этого, если он ещё идёт.
    private func upcomingMonthEnd(_ month: Int) -> Date {
        let year = time.calendar.component(.year, from: time.today)
        let end = lastDay(month: month, year: year)
        return end >= time.today ? end : lastDay(month: month, year: year + 1)
    }

    /// Конец ближайшего сезона, который ещё не кончился.
    private func seasonEnd(firstMonth: Int) -> Date {
        let year = time.calendar.component(.year, from: time.today)
        for candidate in [year - 1, year, year + 1] {
            let lastMonth = firstMonth + 2
            let end = lastDay(month: (lastMonth - 1) % 12 + 1, year: candidate + (lastMonth - 1) / 12)
            if end >= time.today { return end }
        }
        return time.today
    }
}
