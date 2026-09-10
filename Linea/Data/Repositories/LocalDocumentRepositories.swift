//
//  LocalDocumentRepositories.swift
//  Linea
//
//  SwiftData-backed singleton documents: calibration, user profile, nutrition
//  profile (+ meal log). Each is a tiny JSON blob keyed by name.
//

import Foundation
import SwiftData

/// Shared load/save of one `Codable` document by key.
@MainActor
struct DocumentStore {
    let context: ModelContext

    func load<T: Decodable>(_ type: T.Type, key: String) throws -> T? {
        guard let entity = try fetch(key: key) else { return nil }
        return try DocumentCoding.decoder().decode(T.self, from: entity.payload)
    }

    func save<T: Encodable>(_ value: T, key: String, schemaVersion: Int, now: Date) throws {
        let payload = try DocumentCoding.encoder().encode(value)
        if let entity = try fetch(key: key) {
            entity.payload = payload
            entity.schemaVersion = schemaVersion
            entity.updatedAt = now
        } else {
            context.insert(DocumentEntity(key: key, schemaVersion: schemaVersion, payload: payload, updatedAt: now))
        }
        try context.save()
    }

    private func fetch(key: String) throws -> DocumentEntity? {
        let descriptor = FetchDescriptor<DocumentEntity>(predicate: #Predicate { $0.key == key })
        return try context.fetch(descriptor).first
    }
}

@MainActor
final class LocalCalibrationRepository: CalibrationRepository {
    private let store: DocumentStore
    init(context: ModelContext) { store = DocumentStore(context: context) }

    func load() async throws -> Calibration {
        try store.load(Calibration.self, key: DocumentEntity.Key.calibration) ?? .default
    }

    func save(_ calibration: Calibration) async throws {
        try store.save(calibration, key: DocumentEntity.Key.calibration, schemaVersion: Calibration.schemaVersion, now: Date())
    }
}

@MainActor
final class LocalUserProfileRepository: UserProfileRepository {
    private let store: DocumentStore
    init(context: ModelContext) { store = DocumentStore(context: context) }

    func load() async throws -> UserProfile {
        try store.load(UserProfile.self, key: DocumentEntity.Key.userProfile) ?? .default
    }

    func save(_ profile: UserProfile) async throws {
        try store.save(profile, key: DocumentEntity.Key.userProfile, schemaVersion: UserProfile.schemaVersion, now: Date())
    }
}

@MainActor
final class LocalNutritionRepository: NutritionRepository {
    private let store: DocumentStore
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        store = DocumentStore(context: context)
    }

    func profile() async throws -> NutritionProfile? {
        try store.load(NutritionProfile.self, key: DocumentEntity.Key.nutritionProfile)
    }

    func save(_ profile: NutritionProfile) async throws {
        try store.save(profile, key: DocumentEntity.Key.nutritionProfile, schemaVersion: NutritionProfile.schemaVersion, now: Date())
    }

    func meals(on day: DateInterval) async throws -> [MealLog] {
        let start = day.start
        let end = day.end
        let descriptor = FetchDescriptor<MealLogEntity>(
            predicate: #Predicate { $0.at >= start && $0.at < end },
            sortBy: [SortDescriptor(\.at, order: .forward)]
        )
        return try context.fetch(descriptor).map(\.domain)
    }

    func log(_ meal: MealLog) async throws {
        context.insert(MealLogEntity(from: meal))
        try context.save()
    }
}
