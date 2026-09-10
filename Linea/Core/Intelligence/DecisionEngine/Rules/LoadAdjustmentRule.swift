//
//  LoadAdjustmentRule.swift
//  Linea
//
//  «Сегодня нагрузку лучше немного снизить.» — the one recommendation the day
//  gets when the State Engine says `.reduce`. The rule carries the evidence
//  (sleep and recovery facts) along with the verdict so the text can justify
//  itself; it never phrases anything, the renderer does.
//

import Foundation

nonisolated struct LoadAdjustmentRule: RendererAwarePlanRule {
    let id = "loadAdjustment"
    /// Injected by the engine; a rule with no renderer says nothing rather than
    /// inventing a sentence.
    let renderer: (any TextRenderer)?

    init(renderer: (any TextRenderer)? = nil) {
        self.renderer = renderer
    }

    func bound(to renderer: any TextRenderer) -> any PlanRule {
        LoadAdjustmentRule(renderer: renderer)
    }

    func apply(to plan: inout DayPlan, context: PlanningContext) -> [Recommendation] {
        guard context.state.loadAdvice == .reduce, let renderer else { return [] }

        var facts: [Fact] = [.loadAdvice(.reduce)]
        facts += context.state.facts.filter(Self.isEvidence)

        let titles = plan.blocks
            .filter { $0.kind == .focus && $0.isTop }
            .map(\.title)
        let request = ExplanationRequest(
            moment: .loadAdjustment,
            facts: facts,
            taskTitles: titles,
            localeIdentifier: context.time.locale.identifier,
            hour: context.time.timeOfDay(of: context.time.now).hour,
            userName: context.snapshot.profile.name,
            timeZoneIdentifier: context.time.timeZone.identifier
        )
        let explanation = renderer.render(request)

        return [Recommendation(
            id: "\(plan.id.uuidString)-loadAdjustment",
            kind: .loadAdjustment,
            title: explanation.headline,
            message: explanation.body.isEmpty ? explanation.headline : explanation.body,
            facts: facts,
            actions: [.acceptPlan],
            priority: 10
        )]
    }

    /// Sleep and recovery are the only reasons this rule is allowed to cite.
    private static func isEvidence(_ fact: Fact) -> Bool {
        switch fact {
        case .sleepDuration, .sleepBaseline, .sleepVsUsual, .sleepShortAbsolute, .sleepEfficiency,
             .recovery, .hrvVsUsual, .restingHeartRateVsUsual, .highLoadYesterday:
            return true
        default:
            return false
        }
    }
}
