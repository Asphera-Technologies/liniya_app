//
//  NutritionStore.swift
//  Linea
//
//  View-facing state for the nutrition profile and today's meals. Same shape
//  as `PlanStore`: depends on a repository protocol, exposes domain values and
//  intents, reloads from the repository after each mutation.
//
//  Nutrition matters to Linea beyond itself: meal windows become commitments
//  in the day plan, and «Поел» feeds the energy model. That is why the store
//  notifies the plan after every change.
//

import Foundation
import Observation

@Observable
@MainActor
final class NutritionStore {
    private let repository: NutritionRepository

    private(set) var profile: NutritionProfile
    private(set) var todaysMeals: [MealLog] = []
    private(set) var errorMessage: String?

    /// Called after every change so the day plan can be recomputed.
    var onPlanInputsChanged: (@MainActor () async -> Void)?

    init(repository: NutritionRepository) {
        self.repository = repository
        self.profile = NutritionProfile()
    }

    func load() async {
        do {
            profile = try await repository.profile() ?? NutritionProfile()
            let time = TimeContext.live
            todaysMeals = try await repository.meals(on: time.dayInterval(containing: time.now))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(_ profile: NutritionProfile) async {
        do {
            try await repository.save(profile)
            await load()
            await onPlanInputsChanged?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// «Поел»: the fuel component and the meal recommendation both depend on it.
    func logMeal(_ kind: MealKind) async {
        do {
            try await repository.log(MealLog(at: Date(), kind: kind))
            await load()
            await onPlanInputsChanged?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The next meal window of the day that has not been logged yet.
    var nextMeal: MealWindow? {
        let time = TimeContext.live
        let logged = Set(todaysMeals.map(\.kind))
        return profile.mealWindows
            .filter { !logged.contains($0.kind) }
            .sorted { $0.start < $1.start }
            .first { time.date(on: time.today, at: $0.start).addingTimeInterval(TimeInterval($0.durationMinutes * 60)) >= time.now }
            ?? profile.mealWindows.filter { !logged.contains($0.kind) }.sorted { $0.start < $1.start }.first
    }

    /// Products Linea may suggest: preferred minus excluded.
    var allowedProducts: [String] {
        let excluded = Set(profile.excludedProducts.map { $0.lowercased() })
        return profile.preferredProducts.filter { !excluded.contains($0.lowercased()) }
    }
}
