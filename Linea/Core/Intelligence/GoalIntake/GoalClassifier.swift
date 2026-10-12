//
//  GoalClassifier.swift
//  Linea
//
//  Тип цели (`goal_type`), сфера (`scope`) и чья цель (`owner_scope`) — по
//  словам, как тип задачи (ADR-024): небольшие явные словари, офлайн,
//  мгновенно, каждое правило закреплено тестом. Тип и сферу Linea
//  определяет сама и пересчитывает вместе с названием; хранится только
//  выбор человека (`kindOverride`, `scopeOverride`).
//
//  Тип решает, как считать прогресс новой цели и какие у неё стадии:
//  проект — этапами, измеримая — числом, привычка, навык и развитие — без
//  процентов (`GoalKind.typicalMethod`).
//

import Foundation

nonisolated struct GoalClassification: Hashable, Sendable {
    nonisolated enum Reason: Hashable, Sendable {
        /// Тип выбрал человек.
        case chosen
        /// Слово типа: «выпустить», «выучить», «развить».
        case keyword(String)
        /// Число с тем, что считаем: «50 пользователей».
        case number(String)
        /// Регулярность: «3 раза в неделю», «каждый день».
        case frequency(String)
        /// Признаков нет.
        case fallback
    }

    let kind: GoalKind
    let reason: Reason
}

nonisolated struct GoalClassifier: Sendable {
    init() {}

    /// Тип цели: выбор человека, иначе — по названию, а если в нём признаков
    /// нет, — по рассказу.
    func kind(of goal: LineaGoal) -> GoalKind {
        goal.kindOverride ?? classify(title: goal.title, details: Self.story(of: goal)).kind
    }

    func scope(of goal: LineaGoal) -> GoalScope {
        goal.scopeOverride ?? scope(title: goal.title, details: Self.story(of: goal))
    }

    /// Всё, что человек рассказал о цели, кроме названия.
    static func story(of goal: LineaGoal) -> String {
        ([goal.targetState, goal.currentState, goal.details] + goal.successCriteria.map(Optional.some))
            .compactMap { $0 }
            .joined(separator: ". ")
    }

    // MARK: Тип

    func classify(title: String, details: String? = nil) -> GoalClassification {
        if let found = Self.kind(in: title) { return found }
        if let details, let found = Self.kind(in: details) { return found }
        return GoalClassification(kind: .other, reason: .fallback)
    }

    /// Привычка → число → проект → навык → развитие: регулярность важнее
    /// всего («бегать 3 раза в неделю» — не проект), число важнее глагола
    /// («получить 50 пользователей»), но не глагола запуска: «запустить бету
    /// на 50 пользователей» — проект с числом.
    private static func kind(in text: String) -> GoalClassification? {
        let words = RuleBasedGoalAnalyzer.words(text)
        guard !words.isEmpty else { return nil }
        if let frequency = GoalWords.frequency(in: words) {
            return GoalClassification(kind: .habit, reason: .frequency(frequency))
        }
        let project = GoalWords.first(in: words, stems: GoalWords.projectStems, exact: GoalWords.projectWords)
        if let metric = GoalMetricReader.metrics(in: text).first {
            if let project, GoalWords.launchStems.contains(where: project.hasPrefix) {
                return GoalClassification(kind: .project, reason: .keyword(project))
            }
            return GoalClassification(kind: .measurable, reason: .number(GoalProgressText.amount(metric.target, unit: metric.unit)))
        }
        if let project { return GoalClassification(kind: .project, reason: .keyword(project)) }
        if let skill = GoalWords.first(in: words, stems: GoalWords.skillStems, exact: GoalWords.skillWords) {
            return GoalClassification(kind: .skill, reason: .keyword(skill))
        }
        if let growth = GoalWords.first(in: words, stems: GoalWords.growthStems, exact: GoalWords.growthWords) {
            return GoalClassification(kind: .growth, reason: .keyword(growth))
        }
        return nil
    }

    // MARK: Сфера

    /// Сфера: где больше слов — название вдвое весомее рассказа. Поровну —
    /// по порядку `GoalScope.allCases`; слов нет — «Личное».
    func scope(title: String, details: String? = nil) -> GoalScope {
        var score: [GoalScope: Double] = [:]
        for (text, weight) in [(title, 2.0), (details ?? "", 1.0)] {
            for word in RuleBasedGoalAnalyzer.words(text) {
                guard let scope = GoalWords.scope(of: word) else { continue }
                score[scope, default: 0] += weight
            }
        }
        let best = GoalScope.allCases.max { lhs, rhs in
            let left = score[lhs] ?? 0
            let right = score[rhs] ?? 0
            if left != right { return left < right }
            // При равенстве выигрывает тот, кто раньше в списке.
            return GoalScope.allCases.firstIndex(of: lhs)! > GoalScope.allCases.firstIndex(of: rhs)!
        }
        guard let best, (score[best] ?? 0) > 0 else { return .personal }
        return best
    }

    // MARK: Чья цель

    /// «С командой», «всем отделом» — команды; «вместе с женой», «всей
    /// семьёй» — общая; иначе — своя.
    func owner(title: String, details: String? = nil) -> GoalOwnerScope {
        let words = RuleBasedGoalAnalyzer.words(title + " " + (details ?? ""))
        if words.contains(where: { word in GoalWords.teamStems.contains(where: word.hasPrefix) }) { return .team }
        if words.contains("вместе") { return .shared }
        for (index, word) in words.enumerated() where word == "всей" || word == "с" || word == "со" {
            guard words.indices.contains(index + 1) else { continue }
            if GoalWords.companions.contains(words[index + 1]) { return .shared }
        }
        return .personal
    }
}

// MARK: - Словари

nonisolated enum GoalWords {
    /// Запуск продукта: с ним число не делает цель «измеримой».
    static let launchStems = ["запуст", "выпуст", "релиз", "опублик", "выйти", "выход"]

    static let projectStems = launchStems + [
        "сдела", "созда", "постро", "разработ", "открыт", "открыв", "переех", "переезд", "ремонт", "сдать", "сдам",
        "защит", "написа", "подготов", "организ", "провест", "провед", "заверш", "законч", "внедр", "перейт",
        "найти", "получи", "купи", "свадьб", "пробеж", "проплыт", "подня", "издать", "снять", "собрат",
        "testflight", "mvp", "бета", "beta", "стартап",
    ]
    static let projectWords: Set<String> = ["сайт", "сайта", "приложение", "книгу", "дом", "бизнес", "продукт"]

    static let skillStems = [
        "выучи", "учить", "научи", "освои", "изучи", "подтян", "английск", "испанск", "немецк", "французск",
        "китайск", "итальянск", "японск", "курс", "навык", "программир",
    ]
    static let skillWords: Set<String> = ["язык", "языка", "плавать", "водить", "рисовать", "играть"]

    static let growthStems = [
        "развит", "развив", "улучш", "налад", "бренд", "баланс", "уверенн", "спокойн", "осознан", "здоров",
        "энерги", "увереннее", "спокойнее", "дисциплин", "продуктивн",
    ]
    static let growthWords: Set<String> = ["стать", "больше", "меньше", "чаще", "реже"]

    /// Привычка: «каждый день», «ежедневно», «3 раза в неделю», «бросить».
    static func frequency(in words: [String]) -> String? {
        for (index, word) in words.enumerated() {
            let next = words.indices.contains(index + 1) ? words[index + 1] : ""
            if ["каждый", "каждое", "каждую", "каждые"].contains(word), !next.isEmpty { return "\(word) \(next)" }
            if word.hasPrefix("ежедневн") || word.hasPrefix("еженедельн") || word.hasPrefix("регулярн") { return word }
            if word.hasPrefix("привычк") { return word }
            if word == "по", ["утрам", "вечерам", "выходным", "будням"].contains(next) { return "по \(next)" }
            if word == "раз" || word == "раза", next == "в",
               words.indices.contains(index + 2), ["день", "неделю", "месяц"].contains(words[index + 2]) {
                return "\(word) в \(words[index + 2])"
            }
            if ["бросить", "перестать", "отказаться"].contains(word) { return word }
        }
        return nil
    }

    static func first(in words: [String], stems: [String], exact: Set<String>) -> String? {
        words.first { word in exact.contains(word) || stems.contains(where: word.hasPrefix) }
    }

    // MARK: Сфера

    static let workStems = [
        "работ", "клиент", "проект", "бизнес", "компани", "продукт", "карьер", "повышен", "оффер", "офер",
        "стартап", "выручк", "команд", "заказчик", "релиз", "mvp", "сервис",
    ]
    static let workConcepts: Set<String> = [
        "launch", "beta", "testing", "build", "app", "onboarding", "linea", "design", "marketing", "sales", "users", "jobs",
    ]
    static let healthStems = [
        "здоров", "высып", "врач", "анализ", "зуб", "курить", "курени", "алкогол", "медитац", "стресс", "давлен",
        "похуд", "сброс", "килограм",
    ]
    static let healthWords: Set<String> = ["сон", "сна", "спать", "кг", "вес", "веса"]
    static let healthConcepts: Set<String> = ["fitness", "nutrition"]
    static let learningStems = [
        "учеб", "учит", "курс", "выучи", "научи", "освои", "изучи", "экзамен", "университет", "универ",
        "диплом", "сертифик", "навык", "лекци", "программир",
    ]
    static let learningConcepts: Set<String> = ["reading", "language"]
    static let financeStems = [
        "долг", "кредит", "ипотек", "доход", "зарабат", "деньг", "рубл", "зарплат", "подушк", "пенси", "сбереж",
        "инвест", "тысяч", "миллион",
    ]
    static let financeConcepts: Set<String> = ["money"]
    static let relationshipStems = ["семь", "семей", "ребен", "родител", "друз", "отношени", "свидан", "свадьб", "близк", "партнер"]
    static let relationshipWords: Set<String> = [
        "дети", "детей", "детьми", "детям", "сын", "сыну", "сыном", "дочь", "дочке", "дочкой", "мама", "маме", "маму",
        "мамой", "папа", "папе", "папу", "папой", "жена", "жене", "жену", "женой", "муж", "мужу", "мужем", "друг",
        "друга", "другом",
    ]
    static let personalStems = [
        "квартир", "ремонт", "переезд", "переех", "отпуск", "путешеств", "хобби", "рисова", "музык", "гитар",
        "отдых", "машин",
    ]
    static let personalWords: Set<String> = ["дом", "дома", "права"]

    /// Сфера одного слова; служебное и общее — ни одной.
    static func scope(of word: String) -> GoalScope? {
        if let concept = GoalConcepts.concept(of: word) {
            if workConcepts.contains(concept.id) { return .work }
            if healthConcepts.contains(concept.id) { return .health }
            if learningConcepts.contains(concept.id) { return .learning }
            if financeConcepts.contains(concept.id) { return .finance }
        }
        if workStems.contains(where: word.hasPrefix) { return .work }
        if healthWords.contains(word) || healthStems.contains(where: word.hasPrefix) { return .health }
        if learningStems.contains(where: word.hasPrefix) { return .learning }
        if financeStems.contains(where: word.hasPrefix) { return .finance }
        if relationshipWords.contains(word) || relationshipStems.contains(where: word.hasPrefix) { return .relationships }
        if personalWords.contains(word) || personalStems.contains(where: word.hasPrefix) { return .personal }
        return nil
    }

    // MARK: Чья цель

    static let teamStems = ["команд", "коллег", "отдел"]
    /// «с женой», «всей семьёй»: цель на двоих и больше.
    static let companions: Set<String> = [
        "женой", "мужем", "партнером", "партнершей", "семьей", "детьми", "сыном", "дочкой", "дочерью", "другом",
        "подругой", "друзьями", "родителями", "мамой", "папой",
    ]
}
