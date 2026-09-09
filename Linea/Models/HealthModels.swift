//
//  HealthModels.swift
//  Linea
//
//  Domain models for the health context read from Apple Health. Kept separate
//  from HealthKit types so the rest of the app never imports HealthKit.
//

import Foundation
import HealthKit

/// The state of a single health metric.
///
/// Note on "permission not granted": HealthKit deliberately does NOT reveal
/// read authorization status (to avoid leaking whether a user has data). So a
/// denied read and a genuine absence of samples both surface here as `.noData`.
/// Whole-integration authorization/availability is tracked separately on
/// `HealthKitManager.authState`. We never fabricate a value for `.noData`.
enum MetricState<Value: Equatable>: Equatable {
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
struct WorkoutSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let activity: String
    let duration: TimeInterval
    let energyKilocalories: Double?
    let start: Date
}

extension HKWorkoutActivityType {
    /// A short, human-readable name (Russian) for the common activity types.
    var displayName: String {
        switch self {
        case .running: return "Бег"
        case .walking: return "Ходьба"
        case .cycling: return "Велосипед"
        case .hiking: return "Поход"
        case .swimming: return "Плавание"
        case .yoga: return "Йога"
        case .functionalStrengthTraining, .traditionalStrengthTraining:
            return "Силовая"
        case .highIntensityIntervalTraining: return "HIIT"
        case .coreTraining: return "Кор"
        case .pilates: return "Пилатес"
        case .dance, .cardioDance: return "Танцы"
        case .elliptical: return "Эллипс"
        case .rowing: return "Гребля"
        default: return "Тренировка"
        }
    }
}
