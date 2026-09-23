//
//  CheckInValidator.swift
//  Linea
//
//  Фильтр между моделью и человеком для итога дня — родственник
//  `ExplanationValidator`. Модель читает текст, но всё, что она вернула,
//  проверяется: задачи только из списка, длительности в разумных пределах,
//  выжимка без чужих чисел и медицины, в память — не больше трёх коротких
//  фактов. Плохое поле отбрасывается целиком, остальной разбор сохраняется.
//

import Foundation

nonisolated struct CheckInExtractionValidator: Sendable {
    var maxExtra: Int
    var maxModelFacts: Int
    var maxExplicitFacts: Int
    var maxTitleLength: Int
    var maxSummaryLength: Int
    var maxFactLength: Int
    var minimumCyrillicShare: Double

    init(
        maxExtra: Int = 8,
        maxModelFacts: Int = 3,
        maxExplicitFacts: Int = 5,
        maxTitleLength: Int = 80,
        maxSummaryLength: Int = 160,
        maxFactLength: Int = 140,
        minimumCyrillicShare: Double = 0.6
    ) {
        self.maxExtra = maxExtra
        self.maxModelFacts = maxModelFacts
        self.maxExplicitFacts = maxExplicitFacts
        self.maxTitleLength = maxTitleLength
        self.maxSummaryLength = maxSummaryLength
        self.maxFactLength = maxFactLength
        self.minimumCyrillicShare = minimumCyrillicShare
    }

    /// Корни, с которыми факт от модели в память не попадает: здоровье —
    /// не то, что стоит записывать без явной просьбы человека.
    static let sensitiveRoots = ExplanationValidator.forbiddenRoots + ["депресс", "давлен", "анализ", "врач", "терапи", "диабет"]

    func sanitize(_ extraction: CheckInExtraction, request: CheckInRequest) -> CheckInExtraction {
        var result = extraction
        let allowed = Set(request.tasks.map(\.id))
        let transcriptNumbers = ExplanationValidator.numericTokens(in: request.transcript)

        var seenTasks = Set<UUID>()
        result.outcomes = extraction.outcomes.filter { allowed.contains($0.taskID) && seenTasks.insert($0.taskID).inserted }

        var seenTitles = Set<String>()
        result.extra = extraction.extra.compactMap { item -> ExtraWork? in
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (2...maxTitleLength).contains(title.count),
                  seenTitles.insert(RussianWords.normalized(title)).inserted,
                  !request.tasks.contains(where: { RussianWords.similarity($0.title, title) >= 0.5 })
            else { return nil }
            let minutes = item.minutes.flatMap { (1...720).contains($0) ? $0 : nil }
            return ExtraWork(title: RussianWords.capitalizedFirst(title), minutes: minutes)
        }
        result.extra = Array(result.extra.prefix(maxExtra))

        if let minutes = extraction.statedWorkMinutes, !(5...(16 * 60)).contains(minutes) {
            result.statedWorkMinutes = nil
        }

        result.summary = extraction.summary.flatMap { summary -> String? in
            let text = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= maxSummaryLength,
                  ExplanationValidator.cyrillicShare(text) >= minimumCyrillicShare,
                  !Self.containsRoot(text, from: ExplanationValidator.forbiddenRoots),
                  ExplanationValidator.numericTokens(in: text).isSubset(of: transcriptNumbers)
            else { return nil }
            return text
        }

        var facts: [MemoryCandidate] = []
        for candidate in extraction.memory {
            let text = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "«»\"")))
            guard (8...maxFactLength).contains(text.count),
                  ExplanationValidator.cyrillicShare(text) >= minimumCyrillicShare,
                  ExplanationValidator.numericTokens(in: text).isSubset(of: transcriptNumbers),
                  candidate.isExplicit || !Self.containsRoot(text, from: Self.sensitiveRoots),
                  !facts.contains(where: { RussianWords.similarity($0.text, text) >= 0.6 })
            else { continue }
            facts.append(MemoryCandidate(text: RussianWords.capitalizedFirst(text), kind: candidate.kind, isExplicit: candidate.isExplicit))
        }
        let explicit = facts.filter(\.isExplicit).prefix(maxExplicitFacts)
        let fromModel = facts.filter { !$0.isExplicit }.prefix(maxModelFacts)
        result.memory = Array(explicit) + Array(fromModel)
        return result
    }

    static func containsRoot(_ text: String, from roots: [String]) -> Bool {
        let lowercased = RussianWords.normalized(text)
        return roots.contains { lowercased.contains($0) }
    }
}

/// Модель, если она включена и отвечает, иначе правила. Как и
/// `FallbackExplainer`: отказ модели ухудшает качество разбора, но никогда не
/// ломает итог дня.
nonisolated struct FallbackCheckInExtractor: CheckInExtracting {
    let primary: (any CheckInExtracting)?
    let fallback: RuleBasedCheckInExtractor
    let validator: CheckInExtractionValidator

    init(
        primary: (any CheckInExtracting)?,
        fallback: RuleBasedCheckInExtractor = RuleBasedCheckInExtractor(),
        validator: CheckInExtractionValidator = CheckInExtractionValidator()
    ) {
        self.primary = primary
        self.fallback = fallback
        self.validator = validator
    }

    var id: String { primary?.id ?? fallback.id }

    func extract(_ request: CheckInRequest) async throws -> CheckInExtraction {
        let rules = fallback.parse(request)
        guard let primary else { return validator.sanitize(rules, request: request) }
        do {
            let remote = try await primary.extract(request)
            return validator.sanitize(Self.merge(primary: remote, rules: rules), request: request)
        } catch {
            return validator.sanitize(rules, request: request)
        }
    }

    /// Модель главная. От правил берётся то, что нельзя потерять: явные
    /// «запомни» и задачи, которые модель пропустила, — последние без
    /// галочки, чтобы человек решил сам.
    static func merge(primary: CheckInExtraction, rules: CheckInExtraction) -> CheckInExtraction {
        var result = primary
        let known = Set(primary.outcomes.map(\.taskID))
        for outcome in rules.outcomes where !known.contains(outcome.taskID) && outcome.status == .done {
            result.outcomes.append(TaskOutcome(taskID: outcome.taskID, status: .done, isConfident: false))
        }
        for candidate in rules.memory where candidate.isExplicit {
            if let index = result.memory.firstIndex(where: { RussianWords.similarity($0.text, candidate.text) >= 0.5 }) {
                result.memory[index].isExplicit = true
            } else {
                result.memory.insert(candidate, at: 0)
            }
        }
        if result.statedWorkMinutes == nil { result.statedWorkMinutes = rules.statedWorkMinutes }
        if result.rating == nil { result.rating = rules.rating }
        if result.energy == nil { result.energy = rules.energy }
        return result
    }
}
