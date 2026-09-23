//
//  LocalCheckInRepositories.swift
//  Linea
//
//  Дневник итогов дня и долговременная память на SwiftData. Новых сущностей
//  нет: и то и другое — JSON-документы в `DocumentEntity`, как профиль и
//  калибровка. Итог дня лежит под ключом `checkIn.2026-09-22`, память — под
//  `userMemory`. Схема хранилища не меняется, миграция не нужна.
//

import Foundation
import SwiftData

@MainActor
final class LocalCheckInRepository: CheckInRepository {
    static let keyPrefix = "checkIn."

    private let context: ModelContext
    private let store: DocumentStore

    init(context: ModelContext) {
        self.context = context
        store = DocumentStore(context: context)
    }

    func entry(for day: Date) async throws -> CheckInEntry? {
        try store.load(CheckInEntry.self, key: Self.key(for: day))
    }

    func entries(since: Date) async throws -> [CheckInEntry] {
        // Документов немного: несколько настроек и по одному на день итога.
        let decoder = DocumentCoding.decoder()
        return try journalEntities()
            .compactMap { try? decoder.decode(CheckInEntry.self, from: $0.payload) }
            .filter { $0.day >= since }
            .sorted { $0.day < $1.day }
    }

    func save(_ entry: CheckInEntry) async throws {
        try store.save(entry, key: Self.key(for: entry.day), schemaVersion: CheckInEntry.schemaVersion, now: entry.updatedAt)
    }

    func delete(day: Date) async throws {
        let key = Self.key(for: day)
        let descriptor = FetchDescriptor<DocumentEntity>(predicate: #Predicate { $0.key == key })
        for entity in try context.fetch(descriptor) { context.delete(entity) }
        try context.save()
    }

    func deleteAll() async throws {
        for entity in try journalEntities() { context.delete(entity) }
        try context.save()
    }

    private func journalEntities() throws -> [DocumentEntity] {
        let prefix = Self.keyPrefix
        return try context.fetch(FetchDescriptor<DocumentEntity>()).filter { $0.key.hasPrefix(prefix) }
    }

    /// Ключ по местной дате: `checkIn.2026-09-22`.
    static func key(for day: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return keyPrefix + String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

@MainActor
final class LocalMemoryRepository: MemoryRepository {
    private let store: DocumentStore

    init(context: ModelContext) {
        store = DocumentStore(context: context)
    }

    func load() async throws -> UserMemory {
        try store.load(UserMemory.self, key: DocumentEntity.Key.userMemory) ?? .empty
    }

    func save(_ memory: UserMemory) async throws {
        try store.save(memory, key: DocumentEntity.Key.userMemory, schemaVersion: UserMemory.schemaVersion, now: memory.updatedAt ?? Date())
    }
}
