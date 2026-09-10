//
//  Fact.swift
//  Linea
//
//  Typed facts are the ONLY source of numbers and claims for user-facing text.
//  The rule-based explainer renders them deterministically; an LLM explainer
//  may rephrase them but must not introduce numbers that are not here
//  (see ExplanationValidator). Keeping facts typed makes the wow-scenario
//  texts testable on Linux.
//

import Foundation

nonisolated enum Fact: Codable, Hashable, Sendable {
    // Sleep
    case sleepDuration(seconds: TimeInterval)
    case sleepBaseline(seconds: TimeInterval)
    /// Negative delta = slept less than usual.
    case sleepVsUsual(deltaSeconds: TimeInterval, level: UsualLevel)
    case sleepShortAbsolute(seconds: TimeInterval)
    case sleepEfficiency(ratio: Double)

    // Recovery
    case recovery(level: UsualLevel)
    case hrvVsUsual(z: Double)
    case restingHeartRateVsUsual(z: Double)
    case highLoadYesterday

    // Data situation
    case coldStart(days: Int, needed: Int)
    case dataMissing(kind: SignalKind)
    case providerUnavailable(provider: ProviderID, status: ProviderStatus)

    // Energy / advice
    case energy(value: Double, confidence: Double)
    case loadAdvice(LoadAdvice)

    // Plan
    case topTaskCount(Int)
    case hardWorkDeadline(Date)
    case taskPlanned(taskID: UUID, title: String, start: Date, end: Date)
    case taskDeferred(taskID: UUID, title: String, reason: String)
    case workoutPlanned(at: Date)
    case mealWindow(kind: MealKind, start: Date, end: Date)
    case dietRestrictions(count: Int)

    // Nudges
    case behindSchedule(taskID: UUID, title: String, lagMinutes: Int)
    case nextCommitment(title: String, at: Date, minutesLeft: Int)
    case endOfWorkday(minutesLeft: Int)

    // Feedback
    case dayRating(DayRating)
    case calibrationChanged(parameter: String, from: Double, to: Double)
}

nonisolated enum DayRating: String, Codable, Hashable, Sendable, CaseIterable {
    case great, ok, hard

    var title: String {
        switch self {
        case .great: return "Отлично"
        case .ok: return "Нормально"
        case .hard: return "Тяжело"
        }
    }

    /// −1 / 0 / +1 for calibration math.
    var value: Double {
        switch self {
        case .great: return 1
        case .ok: return 0
        case .hard: return -1
        }
    }
}
