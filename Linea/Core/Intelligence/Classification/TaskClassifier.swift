//
//  TaskClassifier.swift
//  Linea
//
//  Какого типа задача (`TaskKind`): по выбору человека, по связи с целью, по
//  словам названия и по тому, назначено ли ей время. Как и разбор итога дня —
//  небольшие явные словари без модели: офлайн, детерминированно, каждое
//  правило закреплено тестом. Модель на телефоне, если появится, станет ещё
//  одной реализацией с тем же ответом.
//
//  Порядок:
//    1. Тип выбрал человек — он и есть.
//    2. Задача связана с целью — это шаг к цели.
//    3. Слова названия: у типа есть основы и фразы с весами, побеждает
//       больший вес, при равенстве — порядок `tieOrder`. Назначенное время
//       немного тянет к обязательству: встреча обычно с кем-то.
//    4. Признаков нет: сложная задача — скорее шаг к цели, иначе разовое.
//

import Foundation

nonisolated struct TaskClassification: Hashable, Sendable {
    nonisolated enum Reason: Hashable, Sendable {
        /// Выбрал человек.
        case chosen
        /// Задача связана с целью.
        case linkedGoal
        /// Слово или фраза названия.
        case keyword(String)
        /// Назначено время, других признаков нет.
        case fixedTime
        /// Сложная, других признаков нет.
        case deepWork
        /// Признаков нет.
        case fallback
    }

    let kind: TaskKind
    /// 0…1 — насколько Linea уверена.
    let confidence: Double
    let reason: Reason
}

nonisolated struct TaskClassifier: Sendable {
    /// При равном весе: реакция на чужое и обещанное важнее для баланса, чем быт.
    static let tieOrder: [TaskKind] = [.incoming, .obligation, .goal, .routine, .maintenance, .standalone]
    /// Сколько добавляет назначенное время к «обязательству».
    static let fixedTimeWeight = 0.5

    init() {}

    func classify(_ task: LineaTask) -> TaskClassification {
        classify(title: task.title, goalID: task.goalID, isFixed: task.isFixed,
                 demand: task.cognitiveDemand, override: task.kindOverride)
    }

    func kind(of task: LineaTask) -> TaskKind {
        classify(task).kind
    }

    func classify(
        title: String,
        goalID: UUID?,
        isFixed: Bool = false,
        demand: CognitiveDemand? = nil,
        override: TaskKind? = nil
    ) -> TaskClassification {
        if let override { return TaskClassification(kind: override, confidence: 1, reason: .chosen) }
        if goalID != nil { return TaskClassification(kind: .goal, confidence: 1, reason: .linkedGoal) }

        let words = RussianWords.tokens(title).filter { !$0.isNumber }.map(\.normalized)
        var scores: [TaskKind: Double] = [:]
        var reasons: [TaskKind: TaskClassification.Reason] = [:]
        func add(_ kind: TaskKind, _ weight: Double, _ reason: TaskClassification.Reason) {
            scores[kind, default: 0] += weight
            if reasons[kind] == nil { reasons[kind] = reason }
        }

        for phrase in TaskKindWords.phrases {
            if let matched = phrase.match(in: words) {
                add(phrase.kind, phrase.weight, .keyword(matched))
            }
        }
        // Каждое слово голосует за тип не больше одного раза.
        for word in words {
            for entry in TaskKindWords.entries where entry.matches(word) {
                add(entry.kind, entry.weight, .keyword(word))
            }
        }
        if isFixed { add(.obligation, Self.fixedTimeWeight, .fixedTime) }

        let ranked = Self.tieOrder
            .compactMap { kind in scores[kind].map { (kind: kind, score: $0) } }
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.score != rhs.element.score ? lhs.element.score > rhs.element.score : lhs.offset < rhs.offset
            }
            .map { $0.element }

        guard let top = ranked.first else {
            if demand == .deep { return TaskClassification(kind: .goal, confidence: 0.45, reason: .deepWork) }
            return TaskClassification(kind: .standalone, confidence: 0.3, reason: .fallback)
        }

        var confidence = top.score >= 1.5 ? 0.9 : top.score >= 1 ? 0.75 : 0.55
        if ranked.count > 1, ranked[1].score >= 0.75 * top.score { confidence -= 0.2 }
        return TaskClassification(kind: top.kind, confidence: confidence, reason: reasons[top.kind] ?? .fallback)
    }
}

/// Сколько займёт задача.
nonisolated enum TaskEstimate {
    /// Оценка человека, а если её нет — обычная для типа задачи: «Оплатить
    /// интернет» не занимает в плане столько же, сколько «Подготовить релиз».
    static func minutes(for task: LineaTask, classifier: TaskClassifier = TaskClassifier()) -> Int {
        if let estimated = task.estimatedMinutes { return max(5, estimated) }
        return classifier.kind(of: task).typicalMinutes
    }
}

// MARK: - Словари

/// Слова типов. Основа совпадает с началом слова («оплат» — «оплатить»,
/// «оплату»); короткие слова — только целиком («кп», «зал»). Слова — строчные,
/// «ё» → «е».
nonisolated enum TaskKindWords {

    nonisolated struct Entry: Sendable {
        let kind: TaskKind
        let weight: Double
        let prefixes: [String]
        let exact: Set<String>

        init(_ kind: TaskKind, weight: Double = 1, prefixes: [String], exact: Set<String> = []) {
            self.kind = kind
            self.weight = weight
            self.prefixes = prefixes
            self.exact = exact
        }

        func matches(_ word: String) -> Bool {
            exact.contains(word) || prefixes.contains { word.hasPrefix($0) }
        }
    }

    /// Несколько слов вместе: «разобрать входящие» — рутина, хотя «входящие»
    /// по отдельности — входящее. Каждая часть — разные слова, порядок любой.
    nonisolated struct Phrase: Sendable {
        let kind: TaskKind
        let weight: Double
        /// Каждая часть — варианты основ, одна из них должна найтись.
        let parts: [[String]]

        init(_ kind: TaskKind, weight: Double = 1.5, _ parts: [[String]]) {
            self.kind = kind
            self.weight = weight
            self.parts = parts
        }

        /// Совпавшие слова через пробел или nil.
        func match(in words: [String]) -> String? {
            var used = Set<Int>()
            var matched: [String] = []
            for part in parts {
                guard let index = words.indices.first(where: { index in
                    !used.contains(index) && part.contains { words[index].hasPrefix($0) }
                }) else { return nil }
                used.insert(index)
                matched.append(words[index])
            }
            return matched.joined(separator: " ")
        }
    }

    static let phrases: [Phrase] = [
        // «Разобрать входящие», «разобрать почту» — разбор потока, а не ответ кому-то.
        Phrase(.routine, [["разобр", "разбер", "разбор"], ["входящ", "почт", "письма", "сообщения", "inbox", "мессендж"]]),
        Phrase(.routine, [["ответ"], ["письма", "почту", "сообщения", "комментари"]]),
        Phrase(.routine, [["почист", "очист"], ["почт", "входящ"]]),
        Phrase(.routine, [["спланир", "планир", "распланир"], ["день", "неделю", "недели", "месяц", "завтра"]]),
        Phrase(.routine, [["обзор", "итоги", "ревью"], ["недели", "дня", "месяца"]]),
        Phrase(.maintenance, [["вынес", "выброс"], ["мусор"]]),
    ]

    static let entries: [Entry] = [
        Entry(.routine, prefixes: [
            "ежедневн", "еженедельн", "ежемесячн", "каждый", "каждую", "каждое", "каждые", "регулярн",
            "ретро", "стендап", "планерк", "дейли", "зарядк", "медитац", "пробежк", "тренировк",
            "растяжк", "дневник", "прогулк", "бассейн", "спортзал",
        ], exact: ["зал", "спорт", "йога", "йогу", "йогой"]),

        Entry(.maintenance, prefixes: [
            "оплат", "заплат", "платеж", "квартплат", "коммунал", "налог", "штраф", "счет", "квитанц",
            "купи", "закуп", "покупк", "продукт", "магазин", "аптек", "лекарств", "заказат", "закажи",
            "ремонт", "почин", "сантехник", "электрик", "уборк", "убрат", "убери", "помыт", "помой",
            "постира", "стирк", "погладит", "пропылесос", "химчистк", "полить",
            "врач", "стоматолог", "дантист", "парикмахер", "постричь", "стрижк", "записатьс",
            "техосмотр", "шиномонтаж", "переобу", "заправ", "страховк", "продлит", "паспорт",
            "пополнит", "подписк", "посылк", "доставк", "банк",
        ]),

        Entry(.obligation, prefixes: [
            "отправ", "сдать", "сдай", "сдач", "предостав", "передат", "передай", "подписат", "подпиши",
            "подписан", "согласова", "выстав", "отчита", "отчет", "доклад", "презентовать",
            "клиент", "заказчик", "партнер", "начальник", "руководител", "шеф", "коллег",
            "встреч", "созвон", "совещан", "переговор", "интервью", "собеседован",
            "договор", "контракт", "дедлайн", "обещал", "обещан", "вернуть", "верни", "отдать", "отдай",
        ], exact: ["кп", "акт", "тз", "долг", "долга"]),

        Entry(.incoming, prefixes: [
            "ответ", "перезвон", "откликн", "отклик", "рассмотр", "заявк", "запрос", "просьб",
            "попросил", "фидбек", "ревью",
        ], exact: ["код-ревью"]),
        // Само по себе «письмо» или «входящие» — слабый признак: их могут и разбирать.
        Entry(.incoming, weight: 0.5, prefixes: ["входящ", "письмо", "сообщени", "звонок"]),

        Entry(.goal, prefixes: [
            "релиз", "разработ", "запуст", "внедр", "спроектир", "проектир", "прототип", "стратег",
            "исследов", "проект", "mvp", "фич", "дизайн", "архитектур", "лендинг", "сайт", "приложени",
            "бизнес-план", "питч", "инвест", "стартап", "статью", "статья", "курс", "изучит",
            "выучит", "освоит", "научит", "диплом", "диссертац", "портфолио", "резюме",
        ]),

        // Личное: семья, друзья, праздники. Слабее остальных — «позвонить
        // клиенту» остаётся обязательством.
        Entry(.standalone, weight: 0.6, prefixes: [
            "позвон", "поздрав", "подар", "друг", "подруг", "мам", "пап", "бабушк", "дедушк",
            "брат", "сестр", "сын", "доч", "семь", "гост", "рождени", "свидан", "кино", "театр", "концерт",
        ]),
    ]
}
