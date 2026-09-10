//
//  NutritionConnector.swift
//  Linea
//
//  Nutrition as a connector, exactly like any future one: it emits signals,
//  adds one component to the state and one rule to the plan. The engines do
//  not import this file and know nothing about food.
//
//  This is where the brief's success criterion becomes code: a short night
//  lowers capacity, a lowered capacity makes lunch earlier and lighter, and
//  the meal window itself takes time away from the plan.
//

import Foundation

nonisolated extension SignalKind {
    /// The user tapped «Поел».
    static let mealLogged: SignalKind = "nutrition.mealLogged"
}

// MARK: - Provider

nonisolated struct NutritionContextProvider: ContextProvider {
    let id: ProviderID = .nutrition
    let displayName = "Питание"
    let provides: Set<SignalKind> = [.commitment, .mealLogged]

    private let profile: NutritionProfile?
    private let meals: [MealLog]

    init(profile: NutritionProfile?, meals: [MealLog]) {
        self.profile = profile
        self.meals = meals
    }

    func fetchContext(_ request: ContextRequest) async throws -> ProviderFetchResult {
        var signals: [ContextSignal] = []
        let time = request.time
        let day = request.day.start

        for window in profile?.mealWindows.sorted(by: { $0.start < $1.start }) ?? [] {
            let start = time.date(on: day, at: window.start)
            let end = start.addingTimeInterval(TimeInterval(window.durationMinutes * 60))
            signals.append(
                ContextSignal(
                    kind: .commitment,
                    value: .interval(nil),
                    start: start,
                    end: end,
                    source: id,
                    attributes: [
                        SignalAttribute.label: window.kind.title,
                        SignalAttribute.commitmentKind: CommitmentKind.meal.rawValue,
                        "mealKind": window.kind.rawValue,
                    ]
                )
            )
        }

        for meal in meals where request.window.contains(meal.at) {
            signals.append(
                ContextSignal(
                    kind: .mealLogged,
                    value: .text(meal.kind.rawValue),
                    start: meal.at,
                    source: id,
                    attributes: ["mealKind": meal.kind.rawValue]
                )
            )
        }

        let status: ProviderStatus = (profile == nil && meals.isEmpty) ? .noData : .ready
        return ProviderFetchResult(signals: signals, status: status)
    }
}

// MARK: - Plan rule

/// Turns the state into concrete food advice. It never invents products:
/// suggestions come from the user's own «подходит» list minus the excluded one.
nonisolated struct NutritionRule: RendererAwarePlanRule {
    let id = "nutrition"
    private let renderer: (any TextRenderer)?

    init(renderer: (any TextRenderer)? = nil) {
        self.renderer = renderer
    }

    func bound(to renderer: any TextRenderer) -> any PlanRule {
        NutritionRule(renderer: renderer)
    }

    func apply(to plan: inout DayPlan, context: PlanningContext) -> [Recommendation] {
        guard let renderer else { return [] }
        let snapshot = context.snapshot
        guard let profile = snapshot.nutrition else { return [] }

        var recommendations: [Recommendation] = []
        let products = Self.products(profile)
        let logged = Set(snapshot.meals.map(\.kind))

        // Lunch earlier and lighter when the day is a reduce day.
        if context.state.loadAdvice == .reduce,
           let meal = plan.blocks.first(where: { $0.kind == .meal }),
           let kind = Self.mealKind(of: meal, profile: profile, time: context.time),
           !logged.contains(kind) {
            let facts: [Fact] = [
                .mealWindow(kind: kind, start: meal.start, end: meal.end),
                .loadAdvice(.reduce),
                .dietRestrictions(count: profile.restrictions.count),
            ]
            let text = renderer.render(
                ExplanationRequest(
                    moment: .meal, facts: facts, taskTitles: products,
                    localeIdentifier: context.time.locale.identifier,
                    hour: context.time.timeOfDay(of: context.time.now).hour,
                    timeZoneIdentifier: context.time.timeZone.identifier
                )
            )
            recommendations.append(
                Recommendation(
                    id: "\(plan.id.uuidString)-meal-\(kind.rawValue)",
                    kind: .meal,
                    message: text.text,
                    facts: facts,
                    actions: [.markMealEaten(kind)],
                    priority: 5
                )
            )
        }

        // Something to eat before training.
        if let workout = snapshot.commitments.first(where: { $0.kind == .workout }) {
            let facts: [Fact] = [.workoutPlanned(at: workout.start)]
            let text = renderer.render(
                ExplanationRequest(
                    moment: .meal, facts: facts, taskTitles: products,
                    localeIdentifier: context.time.locale.identifier,
                    hour: context.time.timeOfDay(of: context.time.now).hour,
                    timeZoneIdentifier: context.time.timeZone.identifier
                )
            )
            recommendations.append(
                Recommendation(
                    id: "\(plan.id.uuidString)-preworkout",
                    kind: .preWorkoutMeal,
                    message: text.text,
                    facts: facts,
                    actions: [.markMealEaten(.snack)],
                    priority: 4
                )
            )
        }

        return recommendations
    }

    /// Up to three things Linea may suggest eating.
    static func products(_ profile: NutritionProfile) -> [String] {
        let excluded = Set(profile.excludedProducts.map { $0.lowercased() })
        return Array(profile.preferredProducts.filter { !excluded.contains($0.lowercased()) }.prefix(3))
    }

    /// Which meal a plan block stands for — matched by its start time.
    private static func mealKind(of block: PlanBlock, profile: NutritionProfile, time: TimeContext) -> MealKind? {
        let blockStart = time.timeOfDay(of: block.start)
        return profile.mealWindows.first { $0.start == blockStart }?.kind
            ?? profile.mealWindows.first { $0.kind.title == block.title }?.kind
    }
}

// MARK: - State analyzer

/// Food as a component of energy: hours without eating drain the tank, and a
/// meal refills it. Weight comes from `EngineConfig.componentWeights[.fuel]`,
/// so the fusion formula itself does not change.
nonisolated struct NutritionFuelAnalyzer: StateAnalyzer {
    let kind: StateComponentKind = .fuel

    /// Hours after a meal during which the user is considered fuelled.
    var fullHours: Double
    /// Hours after which the tank is considered empty.
    var emptyAfterHours: Double

    init(fullHours: Double = 3, emptyAfterHours: Double = 4) {
        self.fullHours = fullHours
        self.emptyAfterHours = emptyAfterHours
    }

    func analyze(_ input: StateInput) -> StateComponent? {
        let now = input.time.now
        let meals = input.snapshot.meals.filter { $0.at <= now }.sorted { $0.at < $1.at }

        if let last = meals.last {
            let hours = now.timeIntervalSince(last.at) / 3600
            let score = StateMath.clamp(1 - max(0, hours - fullHours) / emptyAfterHours)
            return StateComponent(kind: kind, score: score, confidence: 0.6)
        }

        // Nothing logged: only say something once a meal window has clearly passed.
        guard let profile = input.snapshot.nutrition,
              let first = profile.mealWindows.map(\.start).min() else { return nil }
        let windowStart = input.time.date(on: input.time.startOfDay(input.snapshot.day), at: first)
        let hoursLate = now.timeIntervalSince(windowStart) / 3600
        guard hoursLate >= 1 else { return nil }
        return StateComponent(kind: kind, score: StateMath.clamp(0.5 - 0.1 * hoursLate, 0.2, 0.5), confidence: 0.4)
    }
}
