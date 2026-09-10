//
//  Repositories.swift
//  Linea
//
//  Persistence boundaries for the intelligence core (tasks/goals have their
//  own files). Implementations live in Data/Repositories (SwiftData) and in
//  Tests (in-memory). Each is a small document store — no queries by content.
//
//  These protocols are main-actor isolated on purpose: they are backed by
//  SwiftData's `mainContext`. `HealthHistorySource` below is the exception —
//  it really is nonisolated, so it stays `Sendable` and can be read off the
//  main actor while the day is being planned.
//

import Foundation

protocol DayRecordRepository {
    func record(for day: Date) async throws -> DayRecord?
    /// Records with `day >= since`, oldest first.
    func records(since: Date) async throws -> [DayRecord]
    func save(_ record: DayRecord) async throws
}

protocol CalibrationRepository {
    func load() async throws -> Calibration
    func save(_ calibration: Calibration) async throws
}

protocol UserProfileRepository {
    func load() async throws -> UserProfile
    func save(_ profile: UserProfile) async throws
}

protocol NutritionRepository {
    func profile() async throws -> NutritionProfile?
    func save(_ profile: NutritionProfile) async throws
    func meals(on day: DateInterval) async throws -> [MealLog]
    func log(_ meal: MealLog) async throws
}

/// Daily health aggregates for baselines. Implemented by HealthKit history
/// reading (Data/HealthKit) and by fakes in tests.
nonisolated protocol HealthHistorySource: Sendable {
    /// Daily summaries for the `days` local days BEFORE `day` (today excluded).
    func dailySummaries(days: Int, before day: Date, time: TimeContext) async throws -> [DailyHealthSummary]
}
