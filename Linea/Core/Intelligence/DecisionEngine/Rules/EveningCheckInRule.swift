//
//  EveningCheckInRule.swift
//  Linea
//
//  «Как прошёл день?» — the one question that feeds the Feedback Engine. It
//  waits until the user's evening check-in time AND until the last commitment
//  is over (asking mid-workout gets a shrug, not a rating), and disappears the
//  moment the day has been rated.
//

import Foundation

nonisolated struct EveningCheckInRule: RendererAwareNudgeRule {
    let id = "eveningCheckIn"
    let renderer: (any TextRenderer)?

    init(renderer: (any TextRenderer)? = nil) {
        self.renderer = renderer
    }

    func bound(to renderer: any TextRenderer) -> any NudgeRule {
        EveningCheckInRule(renderer: renderer)
    }

    func nudges(_ context: NudgeContext) -> [Nudge] {
        guard let renderer else { return [] }
        // Ответ — это оценка тремя кнопками или итог дня голосом/текстом.
        guard !context.feedback.contains(where: { $0.dayRating != nil || $0.dayReport != nil }) else { return [] }

        let time = context.time
        let profile = context.snapshot.profile
        let day = time.startOfDay(context.plan.day)

        var fireAt = time.date(on: day, at: profile.eveningCheckIn)
        if let lastCommitmentEnd = context.snapshot.commitments.map(\.end).max(), lastCommitmentEnd > fireAt {
            fireAt = lastCommitmentEnd
        }
        // A question scheduled in the past is not a question: either ask now, or
        // (in quiet hours) do not ask at all.
        fireAt = max(fireAt, time.now)
        guard !profile.isQuiet(time.timeOfDay(of: fireAt)) else { return [] }
        guard time.isSameDay(fireAt, day) else { return [] }

        let explanation = renderer.render(ExplanationRequest(
            moment: .evening,
            facts: [],
            taskTitles: [],
            localeIdentifier: time.locale.identifier,
            hour: time.timeOfDay(of: fireAt).hour,
            userName: profile.name,
            timeZoneIdentifier: time.timeZone.identifier
        ))

        return [Nudge(
            id: NudgeIdentity.eveningCheckIn(day: day, time: time),
            kind: .eveningCheckIn, fireAt: fireAt,
            title: explanation.headline, body: explanation.body,
            actions: [.rateDay], cancelWhen: [.dayRated]
        )]
    }
}
