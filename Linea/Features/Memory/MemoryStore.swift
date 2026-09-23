//
//  MemoryStore.swift
//  Linea
//
//  Память Linea для экранов: что Linea знает о человеке и дневник итогов
//  дня. Отсюда же чат и разбор итога берут контекст — через
//  `UserContextBuilder`, в пределах бюджета токенов.
//
//  Всё хранится только на телефоне. Человек видит каждый факт, может его
//  удалить или записать свой, может стереть дневник целиком.
//

import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class MemoryStore {

    private(set) var memory: UserMemory = .empty
    /// Итоги дней за последний год, от новых к старым.
    private(set) var entries: [CheckInEntry] = []
    private(set) var errorMessage: String?

    private let memoryRepository: any MemoryRepository
    private let checkInRepository: any CheckInRepository
    private let consolidator: MemoryConsolidator
    private let contextBuilder: UserContextBuilder
    private let timeProvider: @MainActor () -> TimeContext
    private var isLoaded = false

    init(
        memoryRepository: any MemoryRepository,
        checkInRepository: any CheckInRepository,
        consolidator: MemoryConsolidator = MemoryConsolidator(),
        contextBuilder: UserContextBuilder = UserContextBuilder(),
        time: @escaping @MainActor () -> TimeContext = { .live }
    ) {
        self.memoryRepository = memoryRepository
        self.checkInRepository = checkInRepository
        self.consolidator = consolidator
        self.contextBuilder = contextBuilder
        self.timeProvider = time
    }

    var time: TimeContext { timeProvider() }

    // MARK: Загрузка

    func load() async {
        let time = self.time
        do {
            memory = try await memoryRepository.load()
            let loaded = try await checkInRepository.entries(since: time.adding(days: -365, to: time.today))
            // Старые рассказы сжимаются: текст уходит, итог и выжимка остаются.
            var result: [CheckInEntry] = []
            for entry in loaded {
                let compacted = entry.compacted(asOf: time)
                if compacted != entry { try await checkInRepository.save(compacted) }
                result.append(compacted)
            }
            entries = result.sorted { $0.day > $1.day }
            isLoaded = true
            errorMessage = nil
        } catch {
            LineaLog.storage.error("Память не прочиталась: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func loadIfNeeded() async {
        if !isLoaded { await load() }
    }

    // MARK: Для других экранов

    func entry(for day: Date) -> CheckInEntry? {
        entries.first { time.isSameDay($0.day, day) }
    }

    var todayEntry: CheckInEntry? { entry(for: time.today) }

    /// Короткий список известного — модели, чтобы не предлагала повторы.
    func knownFacts(limit: Int = 12) -> [String] {
        contextBuilder.rankedFacts(memory.facts, query: nil, time: time).prefix(limit).map(\.text)
    }

    /// Блок памяти для запроса к модели, в пределах бюджета.
    func context(for query: String?, budget: UserContextBudget = .standard) -> UserContext {
        contextBuilder.build(memory: memory, journal: entries, query: query, time: time, budget: budget)
    }

    // MARK: Изменения

    /// Итог дня сохранён: новая запись дневника и обновлённая память.
    func store(entry: CheckInEntry, memory updated: UserMemory) async {
        do {
            try await checkInRepository.save(entry)
            try await memoryRepository.save(updated)
            memory = updated
            entries.removeAll { time.isSameDay($0.day, entry.day) }
            entries.append(entry)
            entries.sort { $0.day > $1.day }
            errorMessage = nil
        } catch {
            LineaLog.storage.error("Итог дня не сохранился: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// «Запомни, что…» из чата или факт, записанный вручную.
    @discardableResult
    func remember(_ candidates: [MemoryCandidate], source: MemorySource) async -> [MemoryFact] {
        await loadIfNeeded()
        let result = consolidator.merge(candidates, into: memory, source: source, time: time)
        await save(result.memory)
        return result.added + result.confirmed
    }

    func addFact(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await remember([MemoryCandidate(text: RussianWords.capitalizedFirst(trimmed), kind: MemoryCommand.kind(of: trimmed), isExplicit: true)], source: .manual)
    }

    func deleteFact(_ fact: MemoryFact) async {
        await save(consolidator.removing(fact.id, from: memory, time: time))
    }

    func deleteEntry(_ entry: CheckInEntry) async {
        do {
            try await checkInRepository.delete(day: entry.day)
            entries.removeAll { $0.id == entry.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// «Стереть всё»: и факты, и дневник.
    func deleteAll() async {
        do {
            try await checkInRepository.deleteAll()
            entries = []
        } catch {
            errorMessage = error.localizedDescription
        }
        await save(UserMemory(facts: [], updatedAt: time.now))
    }

    private func save(_ updated: UserMemory) async {
        do {
            try await memoryRepository.save(updated)
            memory = updated
            errorMessage = nil
        } catch {
            LineaLog.storage.error("Память не сохранилась: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
