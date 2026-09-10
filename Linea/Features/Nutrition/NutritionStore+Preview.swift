//
//  NutritionStore+Preview.swift
//  Linea
//
//  Preview-only factories for the stores that back Nutrition and Profile.
//  Kept out of the stores themselves so those stay free of any SwiftData
//  import, which is what lets the UI depend on protocols only.
//

import Foundation
import SwiftData

extension NutritionStore {
    @MainActor
    static var preview: NutritionStore {
        NutritionStore(repository: LocalNutritionRepository(context: PreviewContainer.shared.mainContext))
    }
}

extension UserProfileStore {
    @MainActor
    static var preview: UserProfileStore {
        UserProfileStore(repository: LocalUserProfileRepository(context: PreviewContainer.shared.mainContext))
    }
}

/// One in-memory container shared by every preview (no disk writes).
enum PreviewContainer {
    @MainActor
    static let shared: ModelContainer = {
        try! ModelContainer(
            for: Schema(LineaSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }()
}

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
