//
//  Models.swift
//  Linea
//
//  Shared value types for still-sample features (Today's schedule, the meal
//  focus). Tasks & goals now live in domain types (see PlanModels.swift) and
//  health metrics in HealthModels.swift.
//

import Foundation

/// A scheduled item on the Today timeline (e.g. "14:00 — Свободно").
/// Sample data in Phase 2 — belongs to the (future) calendar integration.
struct ScheduleItem: Identifiable {
    let id = UUID()
    let time: String
    let title: String
}

/// The day's nutrition focus (e.g. the next meal).
/// Sample data in Phase 2 — belongs to the (future) nutrition integration.
struct MealFocus {
    let period: String   // "Сегодня"
    let meal: String     // "Обед"
}
