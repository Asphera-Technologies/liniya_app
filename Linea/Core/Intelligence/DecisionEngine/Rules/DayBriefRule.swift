//
//  DayBriefRule.swift
//  Linea
//
//  The morning message — the first thing the user reads and the sentence the
//  whole product is judged by:
//
//    «Доброе утро. Сегодня нагрузку лучше немного снизить.
//     У тебя есть 3 приоритетных действия.
//     Самую сложную работу предлагаю сделать до 12:00.»
//
//  It is a rule rather than something the planner writes itself, for the same
//  reason everything else is: the brief is assembled from facts the plan and
//  the state already produced, and the wording lives in one place.
//

import Foundation

nonisolated struct DayBriefRule: RendererAwarePlanRule {
    let id = "dayBrief"
    let renderer: (any TextRenderer)?

    init(renderer: (any TextRenderer)? = nil) {
        self.renderer = renderer
    }

    func bound(to renderer: any TextRenderer) -> any PlanRule {
        DayBriefRule(renderer: renderer)
    }

    func apply(to plan: inout DayPlan, context: PlanningContext) -> [Recommendation] {
        guard let renderer else { return [] }

        // The verdict and the day's shape, plus the evidence behind them.
        var facts: [Fact] = [.loadAdvice(context.state.loadAdvice)]
        facts += plan.facts.filter(Self.isPlanShape)
        facts += context.state.facts.filter(Self.isEvidence)

        let titles = plan.blocks.filter { $0.kind == .focus && $0.isTop }.map(\.title)
        let explanation = renderer.render(
            ExplanationRequest(
                moment: .morning,
                facts: facts,
                taskTitles: titles,
                localeIdentifier: context.time.locale.identifier,
                hour: context.time.timeOfDay(of: context.time.now).hour,
                userName: context.snapshot.profile.name,
                timeZoneIdentifier: context.time.timeZone.identifier
            )
        )

        return [Recommendation(
            id: "\(plan.id.uuidString)-brief",
            kind: .dayBrief,
            title: explanation.headline,
            message: explanation.text,
            facts: facts,
            actions: [.acceptPlan],
            priority: 20
        )]
    }

    /// What the plan says about the day: how many priorities and how late the
    /// hardest work still fits.
    private static func isPlanShape(_ fact: Fact) -> Bool {
        switch fact {
        case .topTaskCount, .hardWorkDeadline: return true
        default: return false
        }
    }

    /// Why Linea says it: sleep, recovery, and honest gaps in the data.
    private static func isEvidence(_ fact: Fact) -> Bool {
        switch fact {
        case .sleepDuration, .sleepBaseline, .sleepVsUsual, .sleepShortAbsolute,
             .recovery, .hrvVsUsual, .restingHeartRateVsUsual, .highLoadYesterday,
             .coldStart, .dataMissing, .providerUnavailable:
            return true
        default:
            return false
        }
    }
}
