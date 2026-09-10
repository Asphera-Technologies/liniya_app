//
//  DocumentEntities.swift
//  Linea
//
//  SwiftData entities for the intelligence core's documents. Each stores one
//  `Codable` value as a JSON blob with a schema version, so the structure of
//  plans, states and calibration can evolve without SwiftData migrations
//  (which cannot be verified without a Mac). Queries never look inside the
//  blob: `day` / `updatedAt` are the only indexed fields.
//

import Foundation
import SwiftData

/// One day of intelligence: snapshot, state, plan, nudges, feedback (`DayRecord`).
@Model
final class DayRecordEntity {
    @Attribute(.unique) var day: Date
    var schemaVersion: Int
    var payload: Data
    var updatedAt: Date

    init(day: Date, schemaVersion: Int, payload: Data, updatedAt: Date) {
        self.day = day
        self.schemaVersion = schemaVersion
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

/// Singleton documents (calibration, user profile, nutrition profile), keyed by name.
@Model
final class DocumentEntity {
    @Attribute(.unique) var key: String
    var schemaVersion: Int
    var payload: Data
    var updatedAt: Date

    init(key: String, schemaVersion: Int, payload: Data, updatedAt: Date) {
        self.key = key
        self.schemaVersion = schemaVersion
        self.payload = payload
        self.updatedAt = updatedAt
    }

    enum Key {
        static let calibration = "calibration"
        static let userProfile = "userProfile"
        static let nutritionProfile = "nutritionProfile"
    }
}

/// A meal the user marked as eaten («Поел»).
@Model
final class MealLogEntity {
    @Attribute(.unique) var id: UUID
    var at: Date
    var kindRaw: String
    var note: String?

    init(id: UUID, at: Date, kindRaw: String, note: String?) {
        self.id = id
        self.at = at
        self.kindRaw = kindRaw
        self.note = note
    }

    convenience init(from meal: MealLog) {
        self.init(id: meal.id, at: meal.at, kindRaw: meal.kind.rawValue, note: meal.note)
    }

    var domain: MealLog {
        MealLog(id: id, at: at, kind: MealKind(rawValue: kindRaw) ?? .snack, note: note)
    }
}

/// All SwiftData models of the app, in one place for `ModelContainer(for:)`.
enum LineaSchema {
    static let models: [any PersistentModel.Type] = [
        TaskEntity.self,
        GoalEntity.self,
        DayRecordEntity.self,
        DocumentEntity.self,
        MealLogEntity.self,
    ]
}

/// JSON coding shared by the document repositories.
enum DocumentCoding {
    nonisolated static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    nonisolated static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
