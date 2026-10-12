//
//  GoalStructure.swift
//  Linea
//
//  Чем измерить путь к цели — из слов человека, без придумывания:
//    • числа — «50 пользователей», «10 км», «300 тысяч рублей», «с 80 до 75
//      кг»; старт берётся из «Сейчас», если там то же самое: «вешу 82 кг»;
//    • этапы — проверяемые признаки успеха без чисел: «Приложение доступно
//      через TestFlight»;
//    • метод — числа и этапы вместе — «этапы и числа», одно из них — оно
//      само, ничего — как обычно для типа цели (`GoalKind.typicalMethod`);
//    • стадии — свои у цели: у запуска продукта — «Исследование → Разработка
//      → Подготовка запуска → Тестирование → Запуск → Рост», у личного бренда,
//      языка, бега — свои. Текущую стадию Linea выбирает, только если о ней
//      сказано в «Сейчас»: «прототип готов» — разработка.
//
//  Весов этапов Linea не ставит: уверенно их знает только человек.
//

import Foundation

// MARK: - Числа

nonisolated enum GoalMetricReader {
    /// Число цели, найденное в словах.
    nonisolated struct Found: Hashable, Sendable {
        /// «с 80 до 75 кг» — 80; иначе nil.
        var start: Double?
        var target: Double
        var unit: String
    }

    static let multipliers: [String: Double] = [
        "тыс": 1_000, "тысяч": 1_000, "тысячи": 1_000, "тысяча": 1_000, "тысячу": 1_000,
        "млн": 1_000_000, "миллион": 1_000_000, "миллиона": 1_000_000, "миллионов": 1_000_000,
        "млрд": 1_000_000_000,
    ]
    /// После числа — не то, что считают, а время, дата или частота.
    static let notUnits: Set<String> = [
        "числа", "года", "году", "год", "лет", "раз", "раза", "день", "дня", "дней", "неделю", "недели", "недель",
        "месяц", "месяца", "месяцев", "час", "часа", "часов", "минут", "минуты", "минуту", "секунд", "утра", "вечера",
        "ночи", "го", "е", "ое",
    ]
    /// Где кончается то, что считают.
    static let stops: Set<String> = [
        "в", "во", "на", "до", "к", "ко", "и", "или", "для", "через", "за", "по", "с", "со", "у", "от", "из", "а",
        "но", "чтобы", "при", "без", "после", "перед",
    ]
    static let numberWords: [String: Double] = CheckInText.numberWords.merging([
        "сто": 100, "двести": 200, "триста": 300, "четыреста": 400, "пятьсот": 500, "тысяча": 1_000,
    ]) { current, _ in current }
    static let currencies: [Character: String] = ["₽": "₽", "$": "$", "€": "€", "%": "%"]

    /// Числа с тем, что считаем, по порядку.
    static func metrics(in text: String) -> [Found] {
        let tokens = CaptureTokenizer.tokens(text)
        var found: [Found] = []
        var index = 0
        while index < tokens.count {
            guard var (value, last) = number(at: index, in: tokens, text: text) else {
                index += 1
                continue
            }
            // «с 80 до 75 кг»: старт и цель — одно число цели.
            var start: Double?
            if word(at: index - 1, in: tokens) == "с" || word(at: index - 1, in: tokens) == "со",
               word(at: last + 1, in: tokens) == "до", let (target, targetLast) = number(at: last + 2, in: tokens, text: text) {
                start = value
                value = target
                last = targetLast
            }
            if let unit = unit(after: last, in: tokens, text: text), value > 0 {
                found.append(Found(start: start, target: value, unit: unit.text))
                index = unit.last + 1
            } else {
                index = last + 1
            }
        }
        return found
    }

    /// Число цифрами («300 000», «2,5») или словом («пятьдесят»), с
    /// множителем «тысяч», «млн».
    private static func number(at index: Int, in tokens: [CaptureToken], text: String) -> (Double, Int)? {
        guard tokens.indices.contains(index) else { return nil }
        var value: Double
        var last = index
        switch tokens[index].kind {
        case .number(let number):
            value = number
            // «300 000» — разряды через пробел.
            while tokens.indices.contains(last + 1), case .number(let group) = tokens[last + 1].kind,
                  text[tokens[last + 1].range].count == 3,
                  text[tokens[last].range.upperBound..<tokens[last + 1].range.lowerBound].allSatisfy({ $0 == " " || $0 == "\u{00A0}" }) {
                value = value * 1_000 + group
                last += 1
            }
        case .word:
            guard let number = numberWords[tokens[index].word] else { return nil }
            value = number
            if number >= 20, tokens.indices.contains(index + 1), let unit = numberWords[tokens[index + 1].word], unit < 10 {
                value += unit
                last += 1
            }
        default:
            return nil
        }
        if let multiplier = word(at: last + 1, in: tokens).flatMap({ multipliers[$0] }) {
            value *= multiplier
            last += 1
        }
        return (value, last)
    }

    /// Что считаем: одно слово, а если оно прилагательное, — два («платящих
    /// пользователей»). Валюта и проценты — знаком: «300 000 ₽», «20%».
    private static func unit(after last: Int, in tokens: [CaptureToken], text: String) -> (text: String, last: Int)? {
        let tail = text[tokens[last].range.upperBound...].drop { $0 == " " || $0 == "\u{00A0}" }
        if let mark = tail.first, let symbol = currencies[mark] { return (symbol, last) }
        guard let first = word(at: last + 1, in: tokens), !notUnits.contains(first), !stops.contains(first),
              QuickTaskWords.months[first] == nil, GoalLineWords.monthsGenitive[first] == nil else {
            // «200 тысяч» без единицы — тоже число цели: множитель сказал, что это сумма.
            if case .word = tokens[last].kind, multipliers[tokens[last].word] != nil { return ("", last) }
            return nil
        }
        var end = last + 1
        if isAdjective(first), let second = word(at: end + 1, in: tokens), !stops.contains(second), !notUnits.contains(second) {
            end += 1
        }
        let unit = String(text[tokens[last + 1].range.lowerBound..<tokens[end].range.upperBound])
        return (unit, end)
    }

    /// «платящих», «активных», «новых» — прилагательное перед тем, что считаем.
    private static func isAdjective(_ word: String) -> Bool {
        word.count > 4 && ["ых", "их", "ого", "его"].contains { word.hasSuffix($0) }
    }

    private static func word(at index: Int, in tokens: [CaptureToken]) -> String? {
        guard tokens.indices.contains(index), case .word = tokens[index].kind else { return nil }
        return tokens[index].word
    }
}

// MARK: - Этапы, числа, метод

nonisolated enum GoalStructure {
    /// Числа и этапы цели из названия, «Сейчас» и признаков успеха.
    static func derive(
        title: String,
        currentState: String?,
        successCriteria: [String]
    ) -> (metrics: [GoalMetric], milestones: [GoalMilestone]) {
        var metrics: [GoalMetric] = []
        var milestones: [GoalMilestone] = []
        let current = GoalMetricReader.metrics(in: currentState ?? "")

        func addMetric(_ found: GoalMetricReader.Found) {
            let key = RussianWords.normalized(found.unit)
            guard !metrics.contains(where: { RussianWords.normalized($0.unit) == key && $0.target == found.target }) else { return }
            // Старт: сказан («с 80 до 75 кг») или то же самое в «Сейчас»: «вешу
            // 82 кг» и цель «75 кг» — путь вниз; «бегаю по 3 км» и «10 км» —
            // 3 из 10.
            var start = found.start ?? 0
            var currentValue = start
            if found.start == nil, let now = current.first(where: { RussianWords.normalized($0.unit) == key }) {
                if now.target > found.target {
                    start = now.target
                    currentValue = now.target
                } else {
                    currentValue = now.target
                }
            }
            metrics.append(GoalMetric(
                id: DeterministicID.uuid(from: "metric|\(metrics.count)|\(key)|\(found.target)"),
                unit: found.unit, start: start, current: currentValue, target: found.target
            ))
        }

        GoalMetricReader.metrics(in: title).forEach(addMetric)
        let normalizedTitle = RussianWords.normalized(title)
        for criterion in successCriteria {
            let found = GoalMetricReader.metrics(in: criterion)
            if !found.isEmpty {
                found.forEach(addMetric)
                continue
            }
            // Признак без чисел — этап; само название этапом не бывает.
            guard RussianWords.normalized(criterion) != normalizedTitle,
                  !milestones.contains(where: { RussianWords.normalized($0.title) == RussianWords.normalized(criterion) })
            else { continue }
            milestones.append(GoalMilestone(
                id: DeterministicID.uuid(from: "milestone|\(milestones.count)|\(RussianWords.normalized(criterion))"),
                title: criterion
            ))
        }
        return (metrics, milestones)
    }

    /// Как считать прогресс: что есть в словах, иначе — как обычно для типа.
    static func method(kind: GoalKind, metrics: [GoalMetric], milestones: [GoalMilestone]) -> GoalProgressMethod {
        switch (metrics.isEmpty, milestones.isEmpty) {
        case (false, false): return .hybrid
        // Проект с числом — «запустить бету на 50 пользователей»: этапы будут.
        case (false, true): return kind == .project ? .hybrid : .metric
        case (true, false): return .milestones
        case (true, true): return kind.typicalMethod
        }
    }
}

// MARK: - Стадии

nonisolated enum GoalStages {
    /// Набор стадий: тема цели, а если тема не узнана, — тип.
    nonisolated struct Template: Sendable {
        let stages: [String]
        /// Слова «Сейчас», по которым узнаётся стадия: [номер стадии: основы].
        let markers: [Int: [String]]
    }

    static let launch = Template(
        stages: ["Исследование", "Разработка", "Подготовка запуска", "Тестирование", "Запуск", "Рост"],
        markers: [
            // «идея», но не «идёт».
            0: ["идея", "идеи", "идею", "исследов", "гипотез", "интервью", "опрос", "анализ рынк"],
            1: ["прототип", "разработ", "перерабат", "переработ", "дорабат", "пишем", "делаем", "код", "верста", "дизайн"],
            2: ["лендинг", "подготовк", "стор", "маркетинг"],
            3: ["тестир", "бета", "beta", "testflight", "тестировщ"],
            4: ["запустил", "вышли", "опубликовал", "релиз состоял"],
            5: ["растем", "растет", "пользователей уже", "масштаб"],
        ]
    )
    static let brand = Template(
        stages: ["Позиционирование", "Формирование регулярного контента", "Рост аудитории", "Монетизация"],
        markers: [
            0: ["позиционир", "ниш", "о чем писать"],
            1: ["пишу", "веду", "публикую", "посты", "регулярн", "контент"],
            2: ["подписчик", "аудитори", "охват"],
            3: ["монетиз", "реклам", "доход"],
        ]
    )
    static let jobSearch = Template(
        stages: ["Резюме", "Отклики", "Собеседования", "Оффер"],
        markers: [0: ["резюме"], 1: ["отклик", "откликаюсь"], 2: ["собеседов", "интервью"], 3: ["оффер", "офер"]]
    )
    static let hiring = Template(
        stages: ["Вакансия", "Поиск кандидатов", "Собеседования", "Оффер"],
        markers: [0: ["ваканси"], 1: ["кандидат", "ищем"], 2: ["собеседов"], 3: ["оффер", "офер"]]
    )
    static let race = Template(
        stages: ["Базовая форма", "Наращивание объёмов", "Подводка к старту", "Старт"],
        markers: [0: ["начал", "бегаю", "тяжело"], 1: ["объем", "длинн"], 2: ["подводк"], 3: ["старт"]]
    )
    static let language = Template(
        stages: ["Основы", "Регулярная практика", "Свободное общение"],
        markers: [0: ["с нуля", "основ", "алфавит"], 1: ["занимаюсь", "практик", "регулярн"], 2: ["говорю", "общаюсь"]]
    )
    static let money = Template(
        stages: ["Подготовка", "Регулярные накопления", "Финишная прямая"],
        markers: [0: ["бюджет", "считаю"], 1: ["откладыва", "коплю", "регулярн"], 2: ["почти", "осталось"]]
    )

    static func byKind(_ kind: GoalKind) -> Template {
        switch kind {
        case .project:
            return Template(stages: ["Подготовка", "Основная работа", "Завершение"],
                            markers: [0: ["план", "подготов"], 1: ["делаю", "делаем", "в работе", "идет"], 2: ["почти", "заканчива", "осталось"]])
        case .measurable:
            return Template(stages: ["Начало", "Рост", "Финишная прямая"], markers: [2: ["почти", "осталось"]])
        case .habit:
            return Template(stages: ["Начало", "Формирование регулярности", "Привычка закрепилась"],
                            markers: [0: ["начинаю", "пока не"], 1: ["иногда", "через раз", "регулярн"]])
        case .skill:
            return Template(stages: ["Основы", "Регулярная практика", "Уверенное владение"],
                            markers: [0: ["с нуля", "основ"], 1: ["занимаюсь", "практик", "регулярн"]])
        case .growth:
            return Template(stages: ["Начало", "Формирование регулярности", "Устойчивый результат"],
                            markers: [1: ["регулярн", "стараюсь"]])
        case .other:
            return Template(stages: ["Начало", "Основная работа", "Завершение"], markers: [:])
        }
    }

    /// Стадии новой цели.
    static func template(kind: GoalKind, title: String, details: String?) -> Template {
        let words = RuleBasedGoalAnalyzer.words(title + " " + (details ?? ""))
        let concepts = Set(words.compactMap { GoalConcepts.concept(of: $0)?.id })
        func has(_ stems: [String]) -> Bool { words.contains { word in stems.contains(where: word.hasPrefix) } }

        if has(["бренд", "блог", "канал", "подписчик", "контент", "аудитори"]) || concepts.contains("marketing") && kind == .growth {
            return brand
        }
        if has(["нанять", "найм", "наня"]) { return hiring }
        if concepts.contains("jobs") || (has(["работ"]) && has(["найти", "сменить", "оффер"])) { return jobSearch }
        if !concepts.isDisjoint(with: ["launch", "beta", "build", "app", "linea", "onboarding"]), kind == .project || kind == .other {
            return launch
        }
        if has(["марафон", "полумарафон", "забег", "триатлон"]) { return race }
        if concepts.contains("language") { return language }
        if concepts.contains("money"), kind != .habit { return money }
        return byKind(kind)
    }

    static func suggested(kind: GoalKind, title: String, details: String?) -> [String] {
        template(kind: kind, title: title, details: details).stages
    }

    /// Текущая стадия — только если о ней сказано в «Сейчас». Сказано о
    /// нескольких — последняя: «прототип готов, начали тестировать» —
    /// тестирование.
    static func current(kind: GoalKind, title: String, details: String?, currentState: String?) -> String? {
        guard let currentState, !currentState.isEmpty else { return nil }
        let template = template(kind: kind, title: title, details: details)
        let text = " " + RuleBasedGoalAnalyzer.words(currentState).joined(separator: " ")
        let found = template.markers.compactMap { index, markers -> Int? in
            markers.contains { text.contains(" " + $0) } ? index : nil
        }
        guard let index = found.max(), template.stages.indices.contains(index) else { return nil }
        return template.stages[index]
    }
}
