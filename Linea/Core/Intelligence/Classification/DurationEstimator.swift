//
//  DurationEstimator.swift
//  Linea
//
//  Сколько займёт задача, если человек не сказал (ADR-045). Чтобы понимать,
//  куда задача помещается в день, Linea оценивает сама:
//
//    1. По истории человека (`learned`): похожие задачи, закрытые за 90 дней,
//       у которых известно, сколько они заняли на самом деле (от «Начать» до
//       «Завершить»). Похожие — те, что Linea оценила бы по тому же слову
//       («Ответить Ивану» и «Ответить клиенту»), а без такого слова — того же
//       типа. Хватает трёх по слову или пяти по типу — оценка — медиана
//       фактических минут.
//    2. По словам названия (`ai`): «Ответить клиенту» — 10 минут, «Подготовить
//       презентацию» — час, «Подготовить стратегию» — полтора. Если задача
//       начинается с быстрого действия («ответить», «отправить», «оплатить»),
//       её предмет времени не добавляет: «Отправить презентацию» — 10 минут.
//       Иначе берётся самое долгое из найденного.
//    3. Слов не нашлось — обычная длительность типа задачи (`TaskKind`).
//
//  Небольшой явный словарь без модели — как у типа задачи: офлайн,
//  детерминированно, каждое правило закреплено тестом.
//

import Foundation

nonisolated struct DurationEstimator: Sendable {
    /// Сколько похожих задач с известной длительностью нужно, чтобы верить
    /// истории больше, чем словам: по слову и по типу задачи.
    static let minimumSamples = 3
    static let minimumKindSamples = 5
    /// История — за столько дней.
    static let historyDays = 90

    /// Слово, по которому оценивается длительность.
    nonisolated struct Entry: Sendable {
        /// Имя для истории: задачи с одним словом — похожие.
        let key: String
        let minutes: Int
        /// Быстрое действие: в начале названия решает за всё название.
        let isQuickAction: Bool
        let prefixes: [String]
        let exact: Set<String>

        init(_ key: String, _ minutes: Int, quick: Bool = false, prefixes: [String], exact: Set<String> = []) {
            self.key = key
            self.minutes = minutes
            self.isQuickAction = quick
            self.prefixes = prefixes
            self.exact = exact
        }

        func matches(_ word: String) -> Bool {
            exact.contains(word) || prefixes.contains { word.hasPrefix($0) }
        }
    }

    /// Словарь. Основы — начало слова, строчными, «ё» → «е».
    static let entries: [Entry] = [
        // Быстрые действия: ответить, переслать, напомнить, оплатить.
        Entry("ответить", 10, quick: true, prefixes: ["ответ"]),
        Entry("отправить", 10, quick: true, prefixes: ["отправ", "переслат", "перешл", "скинут", "скинь"]),
        Entry("напомнить", 10, quick: true, prefixes: ["напомн", "подтверд", "уточн"]),
        Entry("перезвонить", 10, quick: true, prefixes: ["перезвон"]),
        Entry("позвонить", 15, quick: true, prefixes: ["позвон", "звонок"]),
        Entry("оплатить", 10, quick: true, prefixes: ["оплат", "заплат"]),
        Entry("заказать", 15, quick: true, prefixes: ["заказ", "продлит", "продлен", "записат"]),
        Entry("купить", 30, quick: true, prefixes: ["купит", "купи", "покупк"]),
        // Сообщения и письма.
        Entry("написать", 15, prefixes: ["написат", "напиши"]),
        Entry("сообщение", 10, prefixes: ["сообщен", "смс"]),
        Entry("письмо", 15, prefixes: ["письм"]),
        // Посмотреть, проверить, согласовать.
        Entry("проверить", 30, prefixes: ["провер", "посмотр", "прочита", "согласов", "разобрат", "разбор"]),
        Entry("изучить", 60, prefixes: ["изучит", "изучен"]),
        // Встречи.
        Entry("встреча", 60, prefixes: ["встреч", "созвон", "совещан", "планерк", "интервью", "собеседов"]),
        // Документы.
        Entry("презентация", 60, prefixes: ["презентац"]),
        Entry("отчет", 60, prefixes: ["отчет"]),
        Entry("предложение", 60, prefixes: ["предложен", "резюме"], exact: ["кп", "смета", "смету", "сметы", "смете"]),
        Entry("договор", 30, prefixes: ["договор", "бриф"]),
        Entry("текст", 60, prefixes: ["текст"], exact: ["пост", "посты", "поста"]),
        Entry("статья", 90, prefixes: ["статья", "статью", "статьи", "статей", "доклад"]),
        // Работа, требующая головы.
        Entry("стратегия", 90, prefixes: ["стратег", "исследов", "архитектур"]),
        Entry("анализ", 60, prefixes: ["анализ", "проанализ"]),
        Entry("релиз", 60, prefixes: ["релиз"]),
        Entry("дизайн", 90, prefixes: ["дизайн", "макет", "прототип"]),
        Entry("разработать", 120, prefixes: ["разработ", "реализ"]),
        // Дом и спорт.
        Entry("уборка", 60, prefixes: ["уборк", "убрат", "убрать"]),
        Entry("приготовить", 45, prefixes: ["приготов", "готовк"]),
        Entry("тренировка", 60, prefixes: ["тренировк", "пробежк"], exact: ["зал", "бег"]),
    ]

    private let classifier = TaskClassifier()

    init() {}

    /// Оценка задачи с таким названием: по истории, иначе по словам, иначе по типу.
    func estimate(title: String, kind: TaskKind, history: [LineaTask], time: TimeContext) -> DurationEstimate {
        let entry = Self.entry(for: title)
        let since = time.adding(days: -Self.historyDays, to: time.now)
        let known = history.filter { task in
            task.isDone && task.cancelledAt == nil && task.actualMinutes != nil
                && (task.completedAt.map { $0 >= since && $0 <= time.now } ?? false)
        }
        // Похожие — те, что Linea оценила бы по тому же слову; без слова — того же типа.
        let similar: [Int]
        let needed: Int
        if let entry {
            similar = known.filter { Self.entry(for: $0.title)?.key == entry.key }.compactMap(\.actualMinutes)
            needed = Self.minimumSamples
        } else {
            similar = known.filter { Self.entry(for: $0.title) == nil && classifier.kind(of: $0) == kind }
                .compactMap(\.actualMinutes)
            needed = Self.minimumKindSamples
        }
        if similar.count >= needed {
            return DurationEstimate(minutes: Self.rounded(Self.median(similar)), source: .learned, samples: similar.count)
        }
        return DurationEstimate(minutes: entry?.minutes ?? kind.typicalMinutes, source: .ai, samples: 0)
    }

    /// Оценка по словам и типу — без истории: например, после переименования.
    func rules(title: String, kind: TaskKind) -> Int {
        Self.entry(for: title)?.minutes ?? kind.typicalMinutes
    }

    /// Слово, по которому оценивается задача: быстрое действие в начале — оно;
    /// иначе — самое долгое из найденных; при равенстве — первое.
    static func entry(for title: String) -> Entry? {
        let words = RussianWords.tokens(title).filter { !$0.isNumber }.map(\.normalized)
        guard !words.isEmpty else { return nil }
        if let quick = entries.first(where: { $0.isQuickAction && $0.matches(words[0]) }) {
            return quick
        }
        var best: Entry?
        for word in words {
            for entry in entries where entry.matches(word) {
                if best == nil || entry.minutes > best!.minutes { best = entry }
            }
        }
        return best
    }

    static func median(_ values: [Int]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? Double(sorted[middle]) : Double(sorted[middle - 1] + sorted[middle]) / 2
    }

    /// До пяти минут, но не меньше пяти.
    static func rounded(_ minutes: Double) -> Int {
        max(5, Int((minutes / 5).rounded()) * 5)
    }
}
