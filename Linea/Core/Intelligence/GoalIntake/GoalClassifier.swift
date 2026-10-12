//
//  GoalClassifier.swift
//  Linea
//
//  Тип цели (`goal_type`) и чья она (`scope`: моя, команды, компании) — по
//  словам, как тип задачи (ADR-024): небольшие явные словари, офлайн,
//  мгновенно, каждое правило закреплено тестом. Тип Linea определяет сама и
//  пересчитывает вместе с названием; хранится только выбор человека
//  (`kindOverride`). Чья цель — догадка при создании; человек её
//  подтверждает или меняет, и она хранится (`LineaGoal.scope`).
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

    // MARK: Чья цель

    /// «Довести выручку компании…» — компании; «всей командой», «с
    /// коллегами», «вместе с женой» — команды (семья и партнёр — тоже
    /// команда: цель зависит не только от человека); иначе — своя.
    func scope(title: String, details: String? = nil) -> GoalScope {
        let words = RuleBasedGoalAnalyzer.words(title + " " + (details ?? ""))
        if words.contains(where: { word in
            GoalWords.companyWords.contains(word) || GoalWords.companyStems.contains(where: word.hasPrefix)
        }) { return .company }
        if words.contains(where: { word in GoalWords.teamStems.contains(where: word.hasPrefix) }) { return .team }
        if words.contains("вместе") || words.contains("сообща") { return .team }
        for (index, word) in words.enumerated() where word == "всей" || word == "с" || word == "со" {
            guard words.indices.contains(index + 1) else { continue }
            if GoalWords.companions.contains(words[index + 1]) { return .team }
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

    // MARK: Чья цель

    /// Выручка, компания, фирма: цель всей компании. «Фирма» — целиком:
    /// «фирменный стиль» — не про компанию.
    static let companyStems = ["компани", "организаци", "корпорат", "холдинг", "выручк"]
    static let companyWords: Set<String> = ["фирма", "фирмы", "фирме", "фирму", "фирмой"]
    static let teamStems = ["команд", "коллег", "отдел"]
    /// «с женой», «всей семьёй»: цель на двоих и больше.
    static let companions: Set<String> = [
        "женой", "мужем", "партнером", "партнершей", "семьей", "детьми", "сыном", "дочкой", "дочерью", "другом",
        "подругой", "друзьями", "родителями", "мамой", "папой",
    ]
}
