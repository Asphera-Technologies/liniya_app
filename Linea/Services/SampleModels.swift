//
//  SampleModels.swift
//  Linea
//
//  Value types for still-sample features (Today's schedule, the meal focus).
//  They are NOT part of the domain: real tasks & goals live in
//  Core/Domain/Models/PlanModels.swift, health in HealthModels.swift. These
//  types disappear together with SampleData once calendar/nutrition are real.
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
