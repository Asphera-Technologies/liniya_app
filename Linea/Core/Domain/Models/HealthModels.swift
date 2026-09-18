//
//  HealthModels.swift
//  Linea
//
//  Domain models for the health context read from Apple Health. Kept separate
//  from HealthKit types so the rest of the app (and the Foundation-only core)
//  never imports HealthKit. The `HKWorkoutActivityType.displayName` helper
//  lives in Data/HealthKit/HKWorkoutActivityType+Display.swift.
//

import Foundation

/// The state of a single health metric.
///
/// Note on "permission not granted": HealthKit deliberately does NOT reveal
/// read authorization status (to avoid leaking whether a user has data). So a
/// denied read and a genuine absence of samples both surface here as `.noData`.
/// Whole-integration authorization/availability is tracked separately on
/// `HealthKitManager.authState`. We never fabricate a value for `.noData`.
nonisolated enum MetricState<Value: Equatable & Sendable>: Equatable, Sendable {
    case loading
    case noData
    case value(Value)

    /// The wrapped value if this is `.value`, otherwise nil.
    var unwrapped: Value? {
        if case let .value(v) = self { return v }
        return nil
    }

    func mapValue<T: Equatable>(_ transform: (Value) -> T) -> MetricState<T> {
        switch self {
        case .loading: return .loading
        case .noData: return .noData
        case .value(let v): return .value(transform(v))
        }
    }
}

/// A lightweight summary of a single workout.
nonisolated struct WorkoutSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let activity: String
    let duration: TimeInterval
    let energyKilocalories: Double?
    let start: Date
}
