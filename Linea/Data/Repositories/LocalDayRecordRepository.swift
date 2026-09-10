//
//  LocalDayRecordRepository.swift
//  Linea
//
//  SwiftData-backed `DayRecordRepository`: one JSON document per local day.
//

import Foundation
import SwiftData

@MainActor
final class LocalDayRecordRepository: DayRecordRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func record(for day: Date) async throws -> DayRecord? {
        guard let entity = try fetch(day: day) else { return nil }
        return try DocumentCoding.decoder().decode(DayRecord.self, from: entity.payload)
    }

    func records(since: Date) async throws -> [DayRecord] {
        let descriptor = FetchDescriptor<DayRecordEntity>(
            predicate: #Predicate { $0.day >= since },
            sortBy: [SortDescriptor(\.day, order: .forward)]
        )
        let decoder = DocumentCoding.decoder()
        return try context.fetch(descriptor).compactMap { entity in
            try? decoder.decode(DayRecord.self, from: entity.payload)
        }
    }

    func save(_ record: DayRecord) async throws {
        let payload = try DocumentCoding.encoder().encode(record)
        if let entity = try fetch(day: record.day) {
            entity.payload = payload
            entity.schemaVersion = DayRecord.schemaVersion
            entity.updatedAt = record.updatedAt
        } else {
            context.insert(DayRecordEntity(day: record.day, schemaVersion: DayRecord.schemaVersion,
                                           payload: payload, updatedAt: record.updatedAt))
        }
        try context.save()
    }

    private func fetch(day: Date) throws -> DayRecordEntity? {
        let descriptor = FetchDescriptor<DayRecordEntity>(predicate: #Predicate { $0.day == day })
        return try context.fetch(descriptor).first
    }
}
