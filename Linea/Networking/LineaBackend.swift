//
//  LineaBackend.swift
//  Linea
//
//  The seam between Linea's UI and its (existing) web backend, for the
//  features that are still sample-only after Phase 2.
//
//  Tasks & goals are NO LONGER here — they go through `TaskRepository` /
//  `GoalRepository` (local SwiftData now; remote + sync later). Health goes
//  through `HealthKitManager`. This protocol now covers only the remaining
//  sample surfaces (schedule, nutrition, profile, health nav).
//
//  No production endpoints, auth, or payload shapes are invented. A live
//  implementation needs the real API contract from the backend team.
//

import Foundation

protocol LineaBackend: Sendable {
    func schedule() async -> [ScheduleItem]
    func mealFocus() async -> MealFocus
    func nutritionSections() async -> [LineaRow]
    func healthSections() async -> [LineaRow]
    func profileSections() async -> [LineaRow]
}

/// A backend backed entirely by `SampleData`, isolated from production logic.
struct SampleBackend: LineaBackend {
    func schedule() async -> [ScheduleItem] { SampleData.schedule }
    func mealFocus() async -> MealFocus { SampleData.mealFocus }
    func nutritionSections() async -> [LineaRow] { SampleData.nutritionRows }
    func healthSections() async -> [LineaRow] { SampleData.healthRows }
    func profileSections() async -> [LineaRow] { SampleData.profileRows }
}
