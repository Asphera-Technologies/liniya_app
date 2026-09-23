//
//  RuleBasedCheckInExtractor.swift
//  Linea
//
//  Разбор итога дня без модели: работает офлайн, мгновенно и ничего не
//  отправляет наружу. Он проще модели — синонимов не знает, «разобрал почту»
//  с задачей «Ответить на письма» не свяжет, — поэтому всё неуверенное
//  помечает как неуверенное, а экран проверки такие строки сам не отмечает.
//
//  С моделью он тоже работает: подстраховывает её, если она не ответила, и
//  добавляет явные просьбы «запомни», которые нельзя потерять.
//

import Foundation

nonisolated struct RuleBasedCheckInExtractor: CheckInExtracting {
    let id = "rules"
    /// Какая доля веса названия задачи должна прозвучать в части предложения.
    var mentionThreshold: Double
    var maxExtra: Int

    init(mentionThreshold: Double = 0.5, maxExtra: Int = 6) {
        self.mentionThreshold = mentionThreshold
        self.maxExtra = maxExtra
    }

    func extract(_ request: CheckInRequest) async throws -> CheckInExtraction {
        parse(request)
    }

    func parse(_ request: CheckInRequest) -> CheckInExtraction {
        let clauses = CheckInText.clauses(request.transcript)
        let effective = effectiveStatuses(clauses)

        var outcomes: [UUID: TaskOutcome] = [:]
        var mentionedClauses = Set<Int>()
        var mentionedSentences = Set<Int>()

        for task in request.tasks {
            let title = TitleMatcher(title: task.title)
            var outcome: TaskOutcome?
            var hasFullMatch = false
            for (index, clause) in clauses.enumerated() {
                guard let match = title.match(clause.words, threshold: mentionThreshold) else { continue }
                // «Созвон с поставщиком» не должен закрывать «Созвон с командой»:
                // неполное совпадение уступает полному и не мешает считать эту
                // часть сделанным сверх плана.
                if !match.isFull && hasFullMatch { continue }
                if match.isFull {
                    mentionedClauses.insert(index)
                    mentionedSentences.insert(clause.sentence)
                }

                // Глаголы названия («ответить», «подготовить») — тоже свидетельство,
                // исключаются только ключевые слова.
                let own = CheckInText.status(of: clause.words, ignoring: match.keyIndices)
                let inherited = inheritsStatus(clauses, at: index) ? effective[index - 1] : nil
                if let status = own ?? inherited {
                    // Последнее упоминание побеждает: «начал утром, а вечером доделал».
                    outcome = TaskOutcome(taskID: task.id, status: status, isConfident: match.isFull)
                } else if outcome == nil || (match.isFull && !hasFullMatch) {
                    outcome = TaskOutcome(taskID: task.id, status: .done, isConfident: false)
                }
                hasFullMatch = hasFullMatch || match.isFull
            }
            if let outcome { outcomes[task.id] = outcome }
        }

        let dayTasks = request.tasks.filter { task in
            guard let date = task.date else { return false }
            return request.time.isSameDay(date, request.day)
        }
        for statement in globalStatements(clauses, excluding: mentionedSentences) {
            for task in dayTasks where outcomes[task.id] == nil {
                outcomes[task.id] = TaskOutcome(taskID: task.id, status: statement, isConfident: true)
            }
        }

        let allWords = RussianWords.tokens(request.transcript).map(\.normalized)
        return CheckInExtraction(
            outcomes: request.tasks.compactMap { outcomes[$0.id] },
            extra: extraWork(clauses, excluding: mentionedClauses, globalSentences: globalSentenceIndices(clauses)),
            statedWorkMinutes: statedWorkMinutes(clauses),
            rating: CheckInText.rating(allWords),
            energy: CheckInText.energy(allWords),
            summary: nil,
            memory: MemoryCommand.candidates(in: request.transcript),
            extractorID: id
        )
    }

    // MARK: Статусы частей

    /// Статус каждой части с учётом наследования: «сделал отчёт и презентацию» —
    /// вторая часть без глагола получает «сделано» от первой.
    private func effectiveStatuses(_ clauses: [CheckInClause]) -> [TaskOutcomeStatus?] {
        var result: [TaskOutcomeStatus?] = []
        for (index, clause) in clauses.enumerated() {
            let own = CheckInText.status(of: clause.words)
            let inherited = inheritsStatus(clauses, at: index) ? result[index - 1] : nil
            result.append(own ?? inherited)
        }
        return result
    }

    private func inheritsStatus(_ clauses: [CheckInClause], at index: Int) -> Bool {
        index > 0 && clauses[index].link == .continuation && clauses[index - 1].sentence == clauses[index].sentence
    }

    // MARK: «Всё сделал», «ничего не успел»

    private func globalStatements(_ clauses: [CheckInClause], excluding mentioned: Set<Int>) -> [TaskOutcomeStatus] {
        var result: [TaskOutcomeStatus] = []
        for sentence in Set(clauses.map(\.sentence)).sorted() where !mentioned.contains(sentence) {
            if let statement = globalStatement(in: clauses.filter { $0.sentence == sentence }) {
                result.append(statement)
            }
        }
        // Если прозвучало и то и другое, верить нечему — ничего не отмечаем.
        return Set(result).count == 1 ? [result[0]] : []
    }

    private func globalSentenceIndices(_ clauses: [CheckInClause]) -> Set<Int> {
        Set(Set(clauses.map(\.sentence)).filter { sentence in
            globalStatement(in: clauses.filter { $0.sentence == sentence }) != nil
        })
    }

    private func globalStatement(in sentence: [CheckInClause]) -> TaskOutcomeStatus? {
        let words = sentence.flatMap(\.words)
        if words.contains("ничего"), words.contains(where: CheckInText.negativeWords.contains) {
            return .notDone
        }
        let saysAll = words.contains("все")
        let saysNo = words.contains(where: { $0 == "не" || $0 == "нет" })
        let saysDone = sentence.contains { CheckInText.status(of: $0.words) == .done }
        if saysAll && saysDone && !saysNo { return .done }
        return nil
    }

    // MARK: Сделанное вне списка

    private static let fillerWords: Set<String> = [
        "а", "и", "еще", "потом", "затем", "также", "плюс", "кстати", "ну", "вот", "сегодня",
        "днем", "утром", "вечером", "наконец", "вроде", "типа", "короче", "в", "общем",
        "на", "с", "около", "где", "то", "примерно",
    ]

    private func extraWork(_ clauses: [CheckInClause], excluding mentioned: Set<Int>, globalSentences: Set<Int>) -> [ExtraWork] {
        var result: [ExtraWork] = []
        for (index, clause) in clauses.enumerated() {
            guard !mentioned.contains(index), !globalSentences.contains(clause.sentence),
                  CheckInText.status(of: clause.words) == .done else { continue }

            let words = clause.words
            let durations = CheckInText.durations(in: words)
            let durationIndices = Set(durations.flatMap { Array($0.range) })
            let content = words.enumerated().filter { offset, word in
                !durationIndices.contains(offset) && Self.isContent(word)
            }
            guard !content.isEmpty else { continue }

            var kept = clause.tokens.enumerated().filter { !durationIndices.contains($0.offset) }.map(\.element)
            while let first = kept.first, Self.fillerWords.contains(first.normalized) { kept.removeFirst() }
            while let last = kept.last, Self.fillerWords.contains(last.normalized) || last.isNumber { kept.removeLast() }
            guard !kept.isEmpty, kept.count <= 8 else { continue }

            let title = RussianWords.capitalizedFirst(kept.map(\.original).joined(separator: " "))
            result.append(ExtraWork(title: title, minutes: durations.first?.minutes))
            if result.count >= maxExtra { break }
        }
        return result
    }

    /// Слово о деле, а не о настроении и не служебное.
    private static func isContent(_ word: String) -> Bool {
        guard word.count >= 3, !RussianWords.stopWords.contains(word), !fillerWords.contains(word) else { return false }
        if CheckInText.positiveStems.contains(where: { word.hasPrefix($0) }) || CheckInText.positiveWords.contains(word) { return false }
        let mood = CheckInText.hardStems + CheckInText.greatStems + CheckInText.okStems
            + CheckInText.lowEnergyStems + CheckInText.highEnergyStems
        if mood.contains(where: { word.hasPrefix($0) }) || CheckInText.greatWords.contains(word) { return false }
        if CheckInText.workStems.contains(where: { word.hasPrefix($0) }) { return false }
        return !CheckInText.isUnit(word)
    }

    // MARK: Объём работы

    /// Объём со слов человека: «работал часов шесть», «всего часа четыре».
    /// Если в предложении про работу несколько длительностей — они складываются
    /// («над отчётом два часа, потом созвон на час»), но явное «всего» главнее.
    private func statedWorkMinutes(_ clauses: [CheckInClause]) -> Int? {
        var total: Int?
        var summed = 0
        for sentence in Set(clauses.map(\.sentence)).sorted() {
            let words = clauses.filter { $0.sentence == sentence }.flatMap(\.words)
            let durations = CheckInText.durations(in: words)
            guard !durations.isEmpty else { continue }

            if let totalIndex = words.firstIndex(where: CheckInText.totalWords.contains),
               let after = durations.first(where: { $0.range.lowerBound > totalIndex }) ?? durations.last {
                total = max(total ?? 0, after.minutes)
                continue
            }
            let aboutWork = words.contains { word in CheckInText.workStems.contains { word.hasPrefix($0) } }
            if aboutWork { summed += durations.reduce(0) { $0 + $1.minutes } }
        }
        let minutes = total ?? (summed > 0 ? summed : nil)
        guard let minutes, (5...(16 * 60)).contains(minutes) else { return nil }
        return minutes
    }
}

// MARK: - Название задачи в речи

/// Совпадение названия задачи с частью предложения. Слова вроде «сделать»,
/// «подготовить» весят меньше: в «Сделать отчёт» главное — «отчёт».
nonisolated struct TitleMatcher: Sendable {
    nonisolated struct Part: Sendable {
        let stem: String
        let weight: Double
        let isKey: Bool
    }

    nonisolated struct Match: Sendable {
        let indices: Set<Int>
        /// Слова, совпавшие с ключевыми (не глагольными) словами названия.
        let keyIndices: Set<Int>
        /// Прозвучали все ключевые слова названия или хотя бы два из них.
        let isFull: Bool
    }

    static let genericStems: Set<String> = [
        "сдела", "напис", "подго", "закон", "додел", "начат", "прове", "отпра", "ответ",
        "занят", "сходи", "разоб", "решит", "обнов", "почин", "завер", "выпол", "позво",
        "купит", "посмо", "изучи", "довес",
    ]

    let parts: [Part]

    init(title: String) {
        var seen = Set<String>()
        parts = RussianWords.significant(title).compactMap { word in
            let stem = RussianWords.stem(word)
            guard seen.insert(stem).inserted else { return nil }
            let isGeneric = Self.genericStems.contains(stem)
            return Part(stem: stem, weight: isGeneric ? 0.3 : 1, isKey: !isGeneric)
        }
    }

    func match(_ words: [String], threshold: Double) -> Match? {
        guard !parts.isEmpty else { return nil }
        var used = Set<Int>()
        var keyIndices = Set<Int>()
        var weight = 0.0
        var keys = 0
        for part in parts {
            guard let index = words.indices.first(where: { !used.contains($0) && RussianWords.word(words[$0], matches: part.stem) }) else { continue }
            used.insert(index)
            weight += part.weight
            if part.isKey {
                keys += 1
                keyIndices.insert(index)
            }
        }
        let total = parts.reduce(0) { $0 + $1.weight }
        let keyCount = parts.filter(\.isKey).count
        // Длинное название не требует, чтобы его пересказали целиком.
        let required = min(threshold * total, 2.0)
        guard weight >= required, weight > 0, keyCount == 0 || keys > 0 else { return nil }
        let isFull = keyCount == 0 ? used.count == parts.count : (keys == keyCount || keys >= 2)
        return Match(indices: used, keyIndices: keyIndices, isFull: isFull)
    }
}
