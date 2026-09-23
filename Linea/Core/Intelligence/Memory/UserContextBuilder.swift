//
//  UserContextBuilder.swift
//  Linea
//
//  «Ядро контекста пользователя»: что из памяти и дневника положить в запрос
//  к модели, чтобы она знала человека, но запрос не рос вместе с историей.
//
//  Устроено как в OpenClaw, но под телефон:
//    • память (факты) — маленький курируемый профиль, как MEMORY.md/USER.md;
//    • последние дни идут выжимками, как стартовый контекст из дневных заметок;
//    • старые дни достаются только поиском по вопросу, как memory_search;
//    • всё вместе укладывается в бюджет токенов, сколько бы дней ни прошло.
//
//  Сырой рассказ в контекст не попадает никогда: из дневника уходят выжимки
//  и короткие цитаты по совпадению.
//

import Foundation

/// Грубая оценка числа токенов для бюджета. Кириллица в токенизаторах
/// современных моделей занимает примерно 2,5 символа на токен, латиница и
/// цифры — около четырёх. Для бюджета важен порядок величины, а не точность.
nonisolated enum TokenEstimator {
    static func estimate(_ text: String) -> Int {
        var cyrillic = 0
        var other = 0
        for scalar in text.unicodeScalars {
            if (0x0400...0x04FF).contains(scalar.value) { cyrillic += 1 } else { other += 1 }
        }
        return Int((Double(cyrillic) / 2.5 + Double(other) / 4).rounded(.up))
    }
}

nonisolated struct UserContextBudget: Sendable, Equatable {
    /// Потолок всего блока памяти в запросе.
    var maxTokens: Int
    var maxFacts: Int
    /// Сколько последних календарных дней идут выжимками без поиска.
    var recentDays: Int
    /// Для скольких самых свежих дней выжимка полная, для остальных — строка итогов.
    var fullDigestDays: Int
    var retrievedDays: Int

    init(maxTokens: Int = 900, maxFacts: Int = 20, recentDays: Int = 7, fullDigestDays: Int = 2, retrievedDays: Int = 3) {
        self.maxTokens = maxTokens
        self.maxFacts = maxFacts
        self.recentDays = recentDays
        self.fullDigestDays = fullDigestDays
        self.retrievedDays = retrievedDays
    }

    static let standard = UserContextBudget()
    /// Для разбора итога дня: модели нужны только известные факты.
    static let checkIn = UserContextBudget(maxTokens: 300, maxFacts: 12, recentDays: 0, fullDigestDays: 0, retrievedDays: 0)
}

nonisolated struct UserContext: Sendable, Equatable {
    let text: String
    let estimatedTokens: Int
    let factCount: Int
    let dayCount: Int

    static let empty = UserContext(text: "", estimatedTokens: 0, factCount: 0, dayCount: 0)
    var isEmpty: Bool { text.isEmpty }
}

/// Поиск по дневнику: какие старые дни относятся к вопросу. Лексический
/// BM25-подобный счёт по основам слов, умноженный на свежесть с периодом
/// полураспада 30 дней (тот же, что у датированных заметок в OpenClaw).
nonisolated struct JournalSearch: Sendable {
    var halfLifeDays: Double
    var snippetLength: Int

    init(halfLifeDays: Double = 30, snippetLength: Int = 160) {
        self.halfLifeDays = halfLifeDays
        self.snippetLength = snippetLength
    }

    nonisolated struct Hit: Sendable {
        let entry: CheckInEntry
        let score: Double
        /// Предложение из рассказа, где нашлось совпадение, если его нет в выжимке.
        let snippet: String?
    }

    func search(_ query: String, in entries: [CheckInEntry], time: TimeContext, limit: Int) -> [Hit] {
        let queryStems = RussianWords.stems(query)
        guard !queryStems.isEmpty, limit > 0 else { return [] }

        let documents = entries.map { entry in (entry, Set(RussianWords.significant(Self.text(of: entry)))) }
        let count = Double(documents.count)
        var frequency: [String: Int] = [:]
        for stem in queryStems {
            frequency[stem] = documents.filter { _, words in words.contains { RussianWords.word($0, matches: stem) } }.count
        }

        let hits = documents.compactMap { entry, words -> Hit? in
            var matched: [String] = []
            var score = 0.0
            for stem in queryStems.sorted() where words.contains(where: { RussianWords.word($0, matches: stem) }) {
                matched.append(stem)
                score += log(1 + count / Double(max(1, frequency[stem] ?? 1)))
            }
            guard score > 0 else { return nil }
            let age = Double(max(0, time.days(from: entry.day, to: time.today)))
            let recency = pow(0.5, age / halfLifeDays)
            // Старый, но точный ответ не должен проигрывать вчерашнему шуму.
            return Hit(entry: entry, score: score * (0.5 + 0.5 * recency), snippet: snippet(for: matched, in: entry))
        }

        return hits.sorted { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.entry.day > rhs.entry.day
        }
        .prefix(limit)
        .map { $0 }
    }

    static func text(of entry: CheckInEntry) -> String {
        [entry.digest, entry.transcript ?? ""].joined(separator: " ")
    }

    /// Цитата нужна, только если выжимка сама не содержит найденного.
    private func snippet(for stems: [String], in entry: CheckInEntry) -> String? {
        let digestWords = RussianWords.significant(entry.digest)
        let missing = stems.filter { stem in !digestWords.contains { RussianWords.word($0, matches: stem) } }
        guard !missing.isEmpty, let transcript = entry.transcript else { return nil }

        let sentences = transcript
            .split(whereSeparator: { ".!?\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let sentence = sentences.first(where: { sentence in
            let words = RussianWords.significant(sentence)
            return missing.contains { stem in words.contains { RussianWords.word($0, matches: stem) } }
        }) else { return nil }
        return sentence.count > snippetLength ? String(sentence.prefix(snippetLength - 1)) + "…" : sentence
    }
}

nonisolated struct UserContextBuilder: Sendable {
    let digestBuilder: DayDigestBuilder
    let search: JournalSearch

    init(digestBuilder: DayDigestBuilder = DayDigestBuilder(), search: JournalSearch = JournalSearch()) {
        self.digestBuilder = digestBuilder
        self.search = search
    }

    /// Блок «что Linea знает о человеке» для запроса к модели. `query` —
    /// вопрос пользователя: по нему подбираются факты и старые дни.
    func build(memory: UserMemory, journal: [CheckInEntry], query: String?, time: TimeContext, budget: UserContextBudget = .standard) -> UserContext {
        var used = 0
        var sections: [String] = []
        var factCount = 0
        var dayCount = 0

        func take(_ header: String, _ lines: [String], cap: Int) -> [String] {
            var accepted: [String] = []
            var cost = TokenEstimator.estimate(header) + 1
            for line in lines {
                let lineCost = TokenEstimator.estimate(line) + 1
                guard used + cost + lineCost <= min(cap, budget.maxTokens) else { break }
                accepted.append(line)
                cost += lineCost
            }
            if !accepted.isEmpty {
                used += cost
                sections.append(([header] + accepted).joined(separator: "\n"))
            }
            return accepted
        }

        // 1. Память: закреплённое, потом относящееся к вопросу, потом самое устойчивое.
        let facts = rankedFacts(memory.facts, query: query, time: time).prefix(budget.maxFacts)
        factCount = take("Что известно о человеке:", facts.map { "- \($0.text)" }, cap: Int(Double(budget.maxTokens) * 0.45)).count

        // 2. Последние дни — выжимками, свежие подробнее.
        let windowStart = time.adding(days: -budget.recentDays, to: time.today)
        let recent = journal
            .filter { $0.day >= windowStart }
            .sorted { $0.day > $1.day }
        let recentLines = recent.enumerated().map { index, entry -> String in
            let text = index < budget.fullDigestDays ? entry.digest : digestBuilder.headline(for: entry.report, day: entry.day, time: time)
            return "- \(text)"
        }
        dayCount += take("Последние дни:", recentLines, cap: used + Int(Double(budget.maxTokens) * 0.30)).count

        // 3. Старые дни — только если вопрос о них.
        if let query, !query.isEmpty, budget.retrievedDays > 0 {
            let recentIDs = Set(recent.map(\.id))
            let hits = search.search(query, in: journal.filter { !recentIDs.contains($0.id) }, time: time, limit: budget.retrievedDays)
            let lines = hits.map { hit -> String in
                var line = "- \(hit.entry.digest)"
                if let snippet = hit.snippet { line += " Из рассказа: «\(snippet)»" }
                return line
            }
            dayCount += take("Похожие дни раньше:", lines, cap: budget.maxTokens).count
        }

        let text = sections.joined(separator: "\n\n")
        return UserContext(text: text, estimatedTokens: TokenEstimator.estimate(text), factCount: factCount, dayCount: dayCount)
    }

    func rankedFacts(_ facts: [MemoryFact], query: String?, time: TimeContext) -> [MemoryFact] {
        let queryStems = query.map(RussianWords.stems) ?? []
        func relevance(_ fact: MemoryFact) -> Int {
            guard !queryStems.isEmpty else { return 0 }
            let words = RussianWords.significant(fact.text)
            return queryStems.filter { stem in words.contains { RussianWords.word($0, matches: stem) } }.count
        }
        let consolidator = MemoryConsolidator()
        return facts.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            let left = relevance(lhs)
            let right = relevance(rhs)
            if left != right { return left > right }
            let strengthLeft = consolidator.strength(lhs, time: time)
            let strengthRight = consolidator.strength(rhs, time: time)
            if strengthLeft != strengthRight { return strengthLeft > strengthRight }
            return lhs.createdAt < rhs.createdAt
        }
    }
}
