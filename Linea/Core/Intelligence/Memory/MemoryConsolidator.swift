//
//  MemoryConsolidator.swift
//  Linea
//
//  Как предложения «запомнить» становятся памятью. Аналог «dreaming» в
//  OpenClaw, только детерминированный и без модели: похожий факт не
//  дублируется, а получает ещё одно подтверждение; всплывший один раз и давно
//  забывается; сверх лимита вытесняется самый слабый. Закреплённое — то, что
//  человек попросил запомнить сам, — не трогается никогда.
//
//  Модель здесь ничего не удаляет и не переписывает: она только предлагает,
//  а решает код. Так память нельзя «стереть» странным ответом модели.
//

import Foundation

nonisolated struct MemoryConsolidator: Sendable {
    var maxFacts: Int
    /// Похожесть по основам, с которой факт считается уже известным.
    var similarityThreshold: Double
    /// Незакреплённый факт, прозвучавший один раз, забывается через столько дней.
    var forgetAfterDays: Int

    init(maxFacts: Int = 40, similarityThreshold: Double = 0.5, forgetAfterDays: Int = 60) {
        self.maxFacts = maxFacts
        self.similarityThreshold = similarityThreshold
        self.forgetAfterDays = forgetAfterDays
    }

    nonisolated struct Result: Sendable {
        let memory: UserMemory
        /// Новые факты, которые остались в памяти.
        let added: [MemoryFact]
        /// Уже известные факты, получившие подтверждение.
        let confirmed: [MemoryFact]
    }

    func merge(_ candidates: [MemoryCandidate], into memory: UserMemory, source: MemorySource, time: TimeContext) -> Result {
        var facts = memory.facts
        var addedIDs: [UUID] = []
        var confirmedIDs: [UUID] = []

        for candidate in candidates {
            let text = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let pinned = candidate.isExplicit || source == .manual

            if let index = facts.firstIndex(where: { isSame($0.text, text) }) {
                facts[index].confirmations += 1
                facts[index].lastConfirmedAt = time.now
                if pinned {
                    facts[index].isPinned = true
                    // Явная формулировка человека точнее догадки модели.
                    facts[index].text = text
                }
                confirmedIDs.append(facts[index].id)
            } else {
                let fact = MemoryFact(
                    id: DeterministicID.uuid(from: "fact|\(text)|\(Int(time.now.timeIntervalSince1970))"),
                    text: text,
                    kind: candidate.kind,
                    source: source,
                    createdAt: time.now,
                    isPinned: pinned
                )
                facts.append(fact)
                addedIDs.append(fact.id)
            }
        }

        facts = capped(forgetting(facts, time: time), time: time)
        let byID = Dictionary(facts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Result(
            memory: UserMemory(facts: facts, updatedAt: time.now),
            added: addedIDs.compactMap { byID[$0] },
            confirmed: confirmedIDs.compactMap { byID[$0] }
        )
    }

    /// Человек удалил факт на экране «Память».
    func removing(_ id: UUID, from memory: UserMemory, time: TimeContext) -> UserMemory {
        UserMemory(facts: memory.facts.filter { $0.id != id }, updatedAt: time.now)
    }

    func isSame(_ lhs: String, _ rhs: String) -> Bool {
        RussianWords.normalized(lhs) == RussianWords.normalized(rhs)
            || RussianWords.similarity(lhs, rhs) >= similarityThreshold
    }

    /// Прозвучал один раз и давно — не закономерность, а случай.
    func forgetting(_ facts: [MemoryFact], time: TimeContext) -> [MemoryFact] {
        facts.filter { fact in
            fact.isPinned || fact.confirmations > 1 || time.days(from: fact.lastConfirmedAt, to: time.now) <= forgetAfterDays
        }
    }

    /// Сверх лимита уходят самые слабые незакреплённые факты.
    func capped(_ facts: [MemoryFact], time: TimeContext) -> [MemoryFact] {
        guard facts.count > maxFacts else { return facts }
        let removable = facts.filter { !$0.isPinned }.sorted { lhs, rhs in
            let left = strength(lhs, time: time)
            let right = strength(rhs, time: time)
            if left != right { return left < right }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let removed = Set(removable.prefix(facts.count - maxFacts).map(\.id))
        return facts.filter { !removed.contains($0.id) }
    }

    /// Подтверждения плюс свежесть: вчерашний факт весит как одно лишнее
    /// подтверждение, месячной давности — примерно треть.
    func strength(_ fact: MemoryFact, time: TimeContext) -> Double {
        let age = Double(max(0, time.days(from: fact.lastConfirmedAt, to: time.now)))
        return Double(fact.confirmations) + exp(-age / 30)
    }
}
