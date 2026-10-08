//
//  ConceptGoalMatcher.swift
//  Linea
//
//  Похоже ли, что задача относится к цели. Linea ищет связь сама, но только
//  подсказывает её: «Похоже, относится к: Запустить Линия Beta [Связать]».
//  Связывает человек, а задача без цели остаётся полноценной задачей.
//
//  Сравниваются не слова, а то, о чём они: «Опубликовать сборку в
//  TestFlight» и «Запустить Линия Beta» не делят ни одного слова, но обе —
//  про запуск и бету. Цель читается целиком: название, результат, признаки
//  успеха и рассказ — так, как Linea поняла её при создании.
//
//  Правила — небольшие явные словари, как у разбора строки и типа задачи:
//  офлайн, мгновенно, каждое закреплено тестом. Не уверена — молчит: слабое
//  совпадение («запустить» и только) и две одинаково похожие цели подсказки
//  не дают.
//
//  Оценка: сумма совпавших понятий задачи — с весом того, где понятие стоит у
//  цели (название сильнее рассказа), и того, насколько оно говорит о связи
//  (общий глагол «запустить» слабее предмета «бета»), — делённая на корень из
//  числа понятий задачи: длинное название не тонет, но и одно случайное
//  слово из пяти не решает.
//

import Foundation

/// Группа слов об одном и том же: «запустить», «релиз», «опубликовать» —
/// запуск.
nonisolated struct GoalConcept: Hashable, Sendable {
    let id: String
    /// Начала слов: «опублик» — «опубликовать», «опубликуем».
    let stems: [String]
    /// Короткие слова целиком: «кп», «бета», «зал».
    let words: Set<String>
    /// Насколько совпадение по группе говорит о связи.
    let weight: Double

    func contains(_ word: String) -> Bool {
        words.contains(word) || stems.contains { word.hasPrefix($0) }
    }
}

nonisolated enum GoalConcepts {
    static let all: [GoalConcept] = [
        // Общий глагол: «Запустить стиральную машину» — не про запуск продукта.
        GoalConcept(id: "launch", stems: ["запуск", "запуст", "запущ", "релиз", "зарелиз", "выпуст", "выпуск", "выкат",
                                          "опублик", "публикац", "launch", "release", "деплой", "задепло", "deploy"],
                    words: ["ship"], weight: 0.6),
        GoalConcept(id: "beta", stems: ["testflight", "тестфлайт", "тестировщ", "тестер"],
                    words: ["бета", "бету", "беты", "бете", "бетой", "beta", "бетка", "бетку"], weight: 1),
        GoalConcept(id: "testing", stems: ["тестирован", "протестир", "тестов"],
                    words: ["тест", "тесты", "qa"], weight: 1),
        GoalConcept(id: "build", stems: ["сборк", "сборок", "билд", "build"], words: [], weight: 1),
        GoalConcept(id: "app", stems: ["приложен", "мобильн"], words: ["app", "ios", "android", "айос"], weight: 0.8),
        GoalConcept(id: "onboarding", stems: ["онборд", "onboard"], words: [], weight: 1),
        // Имя самого приложения: «Linea», а по-русски — «Линия». «Линия» —
        // ещё и обычное слово («горячая линия»), поэтому само по себе слабое.
        GoalConcept(id: "linea", stems: ["linea", "линеа", "линея"],
                    words: ["линия", "линию", "линии", "линией"], weight: 0.6),
        GoalConcept(id: "design", stems: ["дизайн", "design", "макет", "прототип", "figma", "фигм"],
                    words: ["ui", "ux"], weight: 1),
        GoalConcept(id: "marketing", stems: ["маркетинг", "реклам", "продвиж", "лендинг", "landing", "рассылк", "таргет"],
                    words: ["пост", "посты", "постов", "сайт", "сайта", "сайте", "smm"], weight: 1),
        GoalConcept(id: "sales", stems: ["продаж", "коммерческ", "сделк"],
                    words: ["кп", "лиды", "лидов", "crm"], weight: 1),
        GoalConcept(id: "users", stems: ["пользовател", "юзер", "аудитор"], words: ["users"], weight: 1),
        GoalConcept(id: "fitness", stems: ["трениров", "спортзал", "фитнес", "пробеж", "бегать", "марафон", "полумарафон",
                                           "плаван", "бассейн", "присед", "отжим", "кардио", "похуд", "спорт"],
                    words: ["зал", "бег", "бега", "бегу", "бегом", "вес", "йога", "йогу", "йогой"], weight: 1),
        GoalConcept(id: "nutrition", stems: ["диет", "калори", "питани"], words: [], weight: 1),
        GoalConcept(id: "reading", stems: ["книг", "читат", "прочит", "чтени", "почит", "дочит"], words: [], weight: 1),
        GoalConcept(id: "language", stems: ["английск", "english", "испанск", "немецк", "французск", "китайск",
                                            "итальянск", "лексик", "граммат", "duolingo", "дуолинго"],
                    words: ["язык", "языка", "языку"], weight: 1),
        GoalConcept(id: "money", stems: ["накоп", "сбережен", "бюджет", "инвест", "вклад"], words: [], weight: 1),
        GoalConcept(id: "jobs", stems: ["ваканс", "собеседов", "кандидат", "резюме", "найм", "наня"], words: [], weight: 1),
    ]

    /// Слова, которые есть почти в любой задаче, — о связи не говорят:
    /// «Подготовить отчёт» и «Подготовить марафон» не про одно.
    static let genericStems: Set<String> = [
        "сдела", "подго", "прове", "напис", "обсуд", "посмо", "начат", "закон", "докон", "обнов", "созда",
        "добав", "запол", "найти", "найди", "решит", "задач", "вопро", "показ", "отпра", "получ", "позво",
        "купит", "купи", "сходи", "схожу", "встре", "нужно", "надо", "хочу", "можно", "новы", "новог", "перв",
        "сегод", "завтр", "утром", "вечер", "недел", "месяц", "работ", "делат", "сдать", "сдаю",
    ]

    static func concept(of word: String) -> GoalConcept? {
        all.first { $0.contains(word) }
    }
}

nonisolated struct ConceptGoalMatcher: GoalMatcher {
    /// Ниже этого Linea не уверена и молчит.
    var threshold: Double
    /// Две цели ближе этого друг к другу — какая из них, непонятно.
    var margin: Double

    /// Где у цели стоит понятие: название сильнее результата, результат —
    /// рассказа о том, что уже есть.
    static let titleWeight = 1.0
    static let targetWeight = 0.9
    static let storyWeight = 0.7

    init(threshold: Double = 0.5, margin: Double = 0.15) {
        self.threshold = threshold
        self.margin = margin
    }

    func bestMatch(for taskTitle: String, in goals: [LineaGoal]) -> GoalMatch? {
        let task = Self.terms(taskTitle)
        guard !task.isEmpty else { return nil }
        let ranked = goals
            .filter { $0.isActive && !$0.isCompleted }
            .map { GoalMatch(goalID: $0.id, score: score(task: task, goal: $0)) }
            .filter { $0.score >= threshold }
            .sorted { $0.score > $1.score }
        guard let best = ranked.first else { return nil }
        // Две цели одинаково похожи — подсказывать наугад нельзя.
        if ranked.count > 1, best.score - ranked[1].score < margin { return nil }
        return best
    }

    /// Насколько задача похожа на цель, 0…; порог — `threshold`.
    func score(task: Set<String>, goal: LineaGoal) -> Double {
        let profile = Self.profile(of: goal)
        let matched = task.reduce(0.0) { sum, term in
            guard let place = profile[term] else { return sum }
            return sum + place * Self.weight(of: term)
        }
        return matched / Double(task.count).squareRoot()
    }

    /// Понятия цели с весом места, где они стоят.
    static func profile(of goal: LineaGoal) -> [String: Double] {
        var profile: [String: Double] = [:]
        func add(_ text: String?, weight: Double) {
            for term in terms(text ?? "") { profile[term] = max(profile[term] ?? 0, weight) }
        }
        add(goal.title, weight: titleWeight)
        add(goal.targetState, weight: targetWeight)
        add(goal.successCriteria.joined(separator: ". "), weight: targetWeight)
        add(goal.currentState, weight: storyWeight)
        add(goal.details, weight: storyWeight)
        return profile
    }

    /// Понятия текста: группа слов («launch»), если слово в группе, иначе
    /// основа слова. Служебные, общие и числа не в счёт.
    static func terms(_ text: String) -> Set<String> {
        var terms = Set<String>()
        for token in RussianWords.tokens(text) where !token.isNumber {
            let word = token.normalized
            if let concept = GoalConcepts.concept(of: word) {
                terms.insert(conceptTerm(concept.id))
                continue
            }
            guard word.count >= 3, !RussianWords.stopWords.contains(word) else { continue }
            let stem = RussianWords.stem(word)
            guard !GoalConcepts.genericStems.contains(stem) else { continue }
            terms.insert(stem)
        }
        return terms
    }

    /// Понятие среди основ слов: «#launch» — с основой не совпадёт.
    static func conceptTerm(_ id: String) -> String { "#" + id }

    /// Вес совпадения: у группы — свой, у простого слова — полный.
    static func weight(of term: String) -> Double {
        guard term.hasPrefix("#") else { return 1 }
        return GoalConcepts.all.first { conceptTerm($0.id) == term }?.weight ?? 1
    }
}
