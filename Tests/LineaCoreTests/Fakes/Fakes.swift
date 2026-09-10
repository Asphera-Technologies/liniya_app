//
//  Fakes.swift
//  LineaCoreTests
//
//  In-memory implementations of the core protocols for tests.
//

import Foundation
@testable import LineaCore

nonisolated struct FakeContextProvider: ContextProvider {
    let id: ProviderID
    var displayName: String { id.rawValue }
    let provides: Set<SignalKind>
    let signals: [ContextSignal]
    let status: ProviderStatus?
    let error: ProviderError?
    let delay: Duration

    init(id: ProviderID = .fixture, signals: [ContextSignal], status: ProviderStatus? = nil, error: ProviderError? = nil, delay: Duration = .zero) {
        self.id = id
        self.provides = Set(signals.map(\.kind))
        self.signals = signals
        self.status = status
        self.error = error
        self.delay = delay
    }

    func fetchContext(_ request: ContextRequest) async throws -> ProviderFetchResult {
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        let window = request.window
        let inWindow = signals.filter { $0.end >= window.start && $0.start <= window.end }
        return ProviderFetchResult(signals: inWindow, status: status)
    }
}

final class InMemoryDayRecordRepository: DayRecordRepository {
    private var records: [Date: DayRecord] = [:]

    init(records: [DayRecord] = []) {
        for r in records { self.records[r.day] = r }
    }

    func record(for day: Date) async throws -> DayRecord? { records[day] }

    func records(since: Date) async throws -> [DayRecord] {
        records.values.filter { $0.day >= since }.sorted { $0.day < $1.day }
    }

    func save(_ record: DayRecord) async throws { records[record.day] = record }
}

final class InMemoryCalibrationRepository: CalibrationRepository {
    private var calibration: Calibration
    init(_ calibration: Calibration = .default) { self.calibration = calibration }
    func load() async throws -> Calibration { calibration }
    func save(_ calibration: Calibration) async throws { self.calibration = calibration }
}

final class InMemoryUserProfileRepository: UserProfileRepository {
    private var profile: UserProfile
    init(_ profile: UserProfile = .default) { self.profile = profile }
    func load() async throws -> UserProfile { profile }
    func save(_ profile: UserProfile) async throws { self.profile = profile }
}

final class InMemoryNutritionRepository: NutritionRepository {
    private var stored: NutritionProfile?
    private var logs: [MealLog] = []
    init(_ profile: NutritionProfile? = nil, meals: [MealLog] = []) {
        stored = profile
        logs = meals
    }
    func profile() async throws -> NutritionProfile? { stored }
    func save(_ profile: NutritionProfile) async throws { stored = profile }
    func meals(on day: DateInterval) async throws -> [MealLog] { logs.filter { day.contains($0.at) } }
    func log(_ meal: MealLog) async throws { logs.append(meal) }
}

nonisolated struct FakeHealthHistorySource: HealthHistorySource {
    let summaries: [DailyHealthSummary]
    let error: Error?

    init(summaries: [DailyHealthSummary], error: Error? = nil) {
        self.summaries = summaries
        self.error = error
    }

    func dailySummaries(days: Int, before day: Date, time: TimeContext) async throws -> [DailyHealthSummary] {
        if let error { throw error }
        let start = time.adding(days: -days, to: time.startOfDay(day))
        return summaries.filter { $0.day >= start && $0.day < time.startOfDay(day) }.sorted { $0.day < $1.day }
    }
}

/// An explainer that returns a scripted body (to exercise validation/fallback).
nonisolated struct ScriptedExplainer: Explainer {
    let id: String
    let headline: String
    let body: String
    let error: Error?
    let delay: Duration

    init(id: String = "scripted", headline: String = "", body: String, error: Error? = nil, delay: Duration = .zero) {
        self.id = id
        self.headline = headline
        self.body = body
        self.error = error
        self.delay = delay
    }

    func explain(_ request: ExplanationRequest) async throws -> Explanation {
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        return Explanation(headline: headline, body: body, explainerID: id)
    }
}

nonisolated struct FakeError: Error, Equatable { let message: String }
