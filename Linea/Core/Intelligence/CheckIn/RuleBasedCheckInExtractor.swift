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
        let matchers = request.tasks.map { TitleMatcher(title: $0.title) }

        // Где прозвучали задачи. Полное совпадение — задача названа; неполное
        // («созвон с поставщиком» при задаче «Созвон с командой») — только намёк.
        var full = Array(repeating: [(task: Int, match: TitleMatcher.Match)](), count: clauses.count)
        var partial = Array(repeating: [(task: Int, match: TitleMatcher.Match)](), count: clauses.count)
        for (clauseIndex, clause) in clauses.enumerated() {
            for (taskIndex, matcher) in matchers.enumerated() {
                guard let match = matcher.match(clause.words, threshold: mentionThreshold) else { continue }
                if match.isFull {
                    full[clauseIndex].append((taskIndex, match))
                } else {
                    partial[clauseIndex].append((taskIndex, match))
                }
            }
        }
        let fullyMentioned = Set(full.flatMap { $0.map(\.task) })

        // Статус каждой части с наследованием: «сделал отчёт и презентацию».
        var effective: [TaskOutcomeStatus?] = []
        for (index, clause) in clauses.enumerated() {
            let keys = full[index].reduce(into: Set<Int>()) { $0.formUnion($1.match.keyIndices) }
            let own = CheckInText.status(of: clause.words, ignoring: keys, mentionsTask: !full[index].isEmpty)
            effective.append(own ?? (inheritsStatus(clauses, at: index) ? effective[index - 1] : nil))
        }

        var outcomes: [Int: (outcome: TaskOutcome, byReference: Bool)] = [:]
        var consumed = Set<Int>()
        var mentionedSentences = Set<Int>()
        var lastMentioned: (sentence: Int, task: Int)?

        for (index, clause) in clauses.enumerated() {
            if lastMentioned?.sentence != clause.sentence { lastMentioned = nil }
            let inherited = inheritsStatus(clauses, at: index) ? effective[index - 1] : nil

            if !full[index].isEmpty {
                consumed.insert(index)
                mentionedSentences.insert(clause.sentence)
                for (taskIndex, match) in full[index] {
                    let taskID = request.tasks[taskIndex].id
                    let own = CheckInText.status(of: clause.words, ignoring: match.keyIndices, mentionsTask: true)
                    if let status = own ?? inherited {
                        // Последнее прямое упоминание побеждает: «начал утром, а вечером доделал отчёт».
                        outcomes[taskIndex] = (TaskOutcome(taskID: taskID, status: status), false)
                    } else if outcomes[taskIndex] == nil {
                        outcomes[taskIndex] = (TaskOutcome(taskID: taskID, status: .done, isConfident: false), false)
                    }
                }
                lastMentioned = (clause.sentence, full[index][full[index].count - 1].task)
                continue
            }

            // «Сел за отчёт…, но в итоге доделал»: действие без названия задачи
            // относится к последней задаче этого предложения, пока о ней не
            // сказано прямо.
            if let status = CheckInText.status(of: clause.words), let last = lastMentioned {
                let current = outcomes[last.task]
                if current == nil || current!.byReference || !current!.outcome.isConfident {
                    outcomes[last.task] = (TaskOutcome(taskID: request.tasks[last.task].id, status: status), true)
                    consumed.insert(index)
                    continue
                }
            }

            // Неполное совпадение — только для задач, которые нигде не названы полностью.
            for (taskIndex, match) in partial[index] where !fullyMentioned.contains(taskIndex) && outcomes[taskIndex] == nil {
                let own = CheckInText.status(of: clause.words, ignoring: match.keyIndices, mentionsTask: true)
                outcomes[taskIndex] = (TaskOutcome(taskID: request.tasks[taskIndex].id, status: own ?? .done, isConfident: false), false)
            }
        }

        let dayTasks = request.tasks.indices.filter { index in
            guard let date = request.tasks[index].date else { return false }
            return request.time.isSameDay(date, request.day)
        }
        for statement in globalStatements(clauses, excluding: mentionedSentences) {
            for index in dayTasks where outcomes[index] == nil {
                outcomes[index] = (TaskOutcome(taskID: request.tasks[index].id, status: statement), false)
            }
        }

        let allWords = RussianWords.tokens(request.transcript).map(\.normalized)
        return CheckInExtraction(
            outcomes: request.tasks.indices.compactMap { outcomes[$0]?.outcome },
            extra: extraWork(clauses, excluding: consumed, globalSentences: globalSentenceIndices(clauses)),
            statedWorkMinutes: statedWorkMinutes(clauses),
            rating: CheckInText.rating(allWords),
            energy: CheckInText.energy(allWords),
            summary: nil,
            memory: MemoryCommand.candidates(in: request.transcript),
            extractorID: id
        )
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
        let statuses = sentence.map { CheckInText.status(of: $0.words) }
        // «Ничего не успел» — да; «ничего не соображал» — нет: нужен глагол завершения.
        if words.contains("ничего"), statuses.contains(.notDone) { return .notDone }
        if words.contains("все"), statuses.contains(.done), !statuses.contains(.notDone), !statuses.contains(.partial) {
            return .done
        }
        return nil
    }

    // MARK: Сделанное вне списка

    private static let fillerWords: Set<String> = [
        "а", "и", "еще", "потом", "затем", "также", "плюс", "кстати", "ну", "вот", "сегодня",
        "днем", "утром", "вечером", "наконец", "вроде", "типа", "короче", "в", "общем",
        "на", "с", "около", "где", "то", "примерно", "итоге", "целом", "вообще", "опять",
        "просто", "может", "наверное", "это", "тоже", "уже",
    ]

    private func extraWork(_ clauses: [CheckInClause], excluding mentioned: Set<Int>, globalSentences: Set<Int>) -> [ExtraWork] {
        var result: [ExtraWork] = []
        for (index, clause) in clauses.enumerated() {
            guard !mentioned.contains(index), !globalSentences.contains(clause.sentence),
                  CheckInText.status(of: clause.words) == .done else { continue }

            let words = clause.words
            let durations = CheckInText.durations(in: words)
            // «В целом поработал часов шесть» — это объём дня, а не отдельное дело.
            let aboutVolume = words.contains { word in CheckInText.workStems.contains { word.hasPrefix($0) } }
            guard !(aboutVolume && !durations.isEmpty) else { continue }
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
