//
//  FallbackExplainer.swift
//  Linea
//
//  Puts a language model in its place. The headline and the evidence lines are
//  always the rule-based ones — those are what the product promises and what
//  the golden tests assert. A model may only rewrite the body, only if it
//  answers in time, and only if the validator lets it through.
//
//  So an unavailable, slow or hallucinating model costs the user nothing.
//

import Foundation

nonisolated struct FallbackExplainer: Explainer {
    let id = "fallback"

    let primary: (any Explainer)?
    let fallback: RuleBasedExplainer
    let timeout: Duration
    let validator: ExplanationValidator

    init(
        primary: (any Explainer)?,
        fallback: RuleBasedExplainer = RuleBasedExplainer(),
        timeout: Duration = .seconds(3),
        validator: ExplanationValidator = ExplanationValidator()
    ) {
        self.primary = primary
        self.fallback = fallback
        self.timeout = timeout
        self.validator = validator
    }

    func explain(_ request: ExplanationRequest) async throws -> Explanation {
        let base = fallback.render(request)
        guard let primary else { return base }

        guard let candidate = await raced(primary, request: request) else { return base }

        let time = TimeContext(now: Date(timeIntervalSince1970: 0), timeZoneIdentifier: request.timeZoneIdentifier)
        let merged = Explanation(
            headline: base.headline,
            body: candidate.body,
            reasons: base.reasons,
            explainerID: candidate.explainerID
        )
        guard validator.validate(merged, facts: request.facts, taskTitles: request.taskTitles, time: time).isValid else {
            return base
        }
        return merged
    }

    /// The model against the clock; the loser is cancelled either way.
    private func raced(_ explainer: any Explainer, request: ExplanationRequest) async -> Explanation? {
        try? await withThrowingTaskGroup(of: Explanation?.self) { group in
            group.addTask { try await explainer.explain(request) }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            let winner = try await group.next() ?? nil
            group.cancelAll()
            return winner
        }
    }
}
