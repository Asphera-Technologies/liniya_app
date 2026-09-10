//
//  RendererAware.swift
//  Linea
//
//  `PlanRule` / `NudgeRule` are pure data contracts (Domain) and deliberately
//  know nothing about text. But a rule that produces a Recommendation or a
//  Nudge needs Russian strings, and a rule must never write them itself.
//
//  So a rule declares that it wants the engine's `TextRenderer` and the engine
//  hands it over at apply time. This keeps the default `[LoadAdjustmentRule()]`
//  in the engine's signature (a rule list stays a plain literal) while leaving
//  the Domain protocols untouched.
//

import Foundation

nonisolated protocol RendererAwarePlanRule: PlanRule {
    /// A copy of this rule bound to the engine's renderer.
    func bound(to renderer: any TextRenderer) -> any PlanRule
}

nonisolated protocol RendererAwareNudgeRule: NudgeRule {
    func bound(to renderer: any TextRenderer) -> any NudgeRule
}

nonisolated extension Array where Element == any PlanRule {
    func bound(to renderer: any TextRenderer) -> [any PlanRule] {
        map { ($0 as? any RendererAwarePlanRule)?.bound(to: renderer) ?? $0 }
    }
}

nonisolated extension Array where Element == any NudgeRule {
    func bound(to renderer: any TextRenderer) -> [any NudgeRule] {
        map { ($0 as? any RendererAwareNudgeRule)?.bound(to: renderer) ?? $0 }
    }
}
