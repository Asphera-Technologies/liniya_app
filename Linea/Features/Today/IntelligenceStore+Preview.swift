//
//  IntelligenceStore+Preview.swift
//  Linea
//
//  Preview-only factory. Previews must never touch HealthKit or the user's
//  real day, so this wires the store to in-memory repositories and an empty
//  health history: the screens render their honest «нет данных» state.
//

import Foundation
import SwiftData

extension IntelligenceStore {
    /// A preview store wired to in-memory repositories and no health data:
    /// previews must never touch HealthKit or the user's real day.
    @MainActor
    static var preview: IntelligenceStore {
        let context = PreviewContainer.shared.mainContext
        let renderer = RuleBasedExplainer()
        let nudgeEngine = NudgeEngine(renderer: renderer)
        return IntelligenceStore(
            planDay: PlanDayUseCase(
                contextEngine: ContextEngine(providers: []),
                decisionEngine: DecisionEngine(rules: [DayBriefRule(), NutritionRule()], renderer: renderer),
                nudgeEngine: nudgeEngine,
                explainer: renderer
            ),
            acceptPlan: AcceptPlanUseCase(nudgeEngine: nudgeEngine),
            checkIn: CheckInUseCase(nudgeEngine: nudgeEngine),
            records: LocalDayRecordRepository(context: context),
            calibrations: LocalCalibrationRepository(context: context),
            profiles: LocalUserProfileRepository(context: context),
            nutritionRepository: LocalNutritionRepository(context: context),
            history: EmptyHealthHistory(),
            planStore: .preview,
            scheduler: nil
        )
    }
}

/// No health history — used by previews only.
private struct EmptyHealthHistory: HealthHistorySource {
    func dailySummaries(days: Int, before day: Date, time: TimeContext) async throws -> [DailyHealthSummary] { [] }
}
