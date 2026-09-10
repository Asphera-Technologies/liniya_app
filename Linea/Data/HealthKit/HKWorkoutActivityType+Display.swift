//
//  HKWorkoutActivityType+Display.swift
//  Linea
//
//  Human-readable (Russian) names for common workout types. This is the only
//  place outside HealthKitManager that imports HealthKit; the domain model
//  (`WorkoutSummary`) carries the resulting string, never the HK type.
//
//  `nonisolated` because the context provider reads it while collecting
//  signals off the main actor: it is a pure mapping with no state to protect.
//

import HealthKit

nonisolated extension HKWorkoutActivityType {
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
