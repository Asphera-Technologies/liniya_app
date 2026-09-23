//
//  TodayView.swift
//  Linea
//
//  The Today screen — the whole wow-scenario in one place:
//    • morning: what Linea sees about the state, the day's plan, «Принять план»;
//    • during the day: the nudge card with the same two answers the
//      notification offers;
//    • evening: «Как прошёл день?» — the check-in by voice or text, or three
//      quick taps, which close the feedback loop.
//
//  The screen composes; it never decides. Every string comes ready from the
//  core (`Recommendation.message`, `Nudge.title/body`), so what the user reads
//  here is exactly what the golden tests assert.
//

import SwiftUI

struct TodayView: View {
    @Environment(AppState.self) private var appState
    @Environment(PlanStore.self) private var plan
    @Environment(IntelligenceStore.self) private var intelligence

    var body: some View {
        NavigationStack {
            LineaScaffold(title: greeting, subtitle: dateSubtitle) {
                if let nudge = intelligence.dueNudge {
                    NudgeCard(nudge: nudge) { action in
                        Task { await intelligence.respond(to: nudge, action: action) }
                    }
                }

                briefSection
                mainToday
                timeline

                if intelligence.isCheckInDue {
                    EveningReviewCard(
                        canRate: intelligence.canRateDay,
                        onTell: { appState.openCheckIn() },
                        onRate: { rating in Task { await intelligence.rateDay(rating) } }
                    )
                } else if let entry = intelligence.todayCheckIn {
                    CheckInSummaryCard(numbers: DayDigestBuilder().numbers(for: entry.report)) {
                        appState.openCheckIn()
                    }
                }

                adviceSection
            }
        }
        .task { await intelligence.refresh(reason: .appeared) }
        .refreshable { await intelligence.refresh(reason: .manual) }
    }

    // MARK: Brief

    @ViewBuilder
    private var briefSection: some View {
        if let brief = intelligence.brief {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "План на сегодня", trailing: intelligence.stateTag)
                Text(brief.message)
                    .font(LineaFont.feature)
                    .foregroundStyle(LineaColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let explanation = brief.explanation, !explanation.isEmpty {
                    Text(explanation)
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !intelligence.reasons.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(intelligence.reasons, id: \.self) { reason in
                            Text(reason)
                                .font(LineaFont.caption)
                                .foregroundStyle(LineaColor.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if intelligence.canAcceptPlan {
                    LineaOutlineButton(title: "Принять план") {
                        Task { await intelligence.acceptPlan() }
                    }
                }
            }
        }
    }

    // MARK: Main task

    private var mainToday: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Главное сегодня")
            if let task = intelligence.topTask ?? plan.topTaskToday {
                Text(task.title)
                    .font(LineaFont.feature)
                    .foregroundStyle(LineaColor.textPrimary)
            } else {
                Text("На сегодня задач нет")
                    .font(LineaFont.feature)
                    .foregroundStyle(LineaColor.textTertiary)
            }
        }
    }

    // MARK: Timeline

    @ViewBuilder
    private var timeline: some View {
        let blocks = intelligence.visibleBlocks
        if !blocks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Дальше", trailing: intelligence.planTag)
                VStack(spacing: 0) {
                    ForEach(blocks) { block in
                        PlanBlockRow(
                            block: block,
                            time: intelligence.time,
                            isDone: intelligence.isDone(block)
                        )
                    }
                }
            }
        }
    }

    // MARK: Advice (nutrition and the like)

    @ViewBuilder
    private var adviceSection: some View {
        let advice = intelligence.advice
        if !advice.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(text: "Советы")
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(advice) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.message)
                                .font(LineaFont.rowTitle)
                                .foregroundStyle(LineaColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !item.actions.isEmpty {
                                HStack(spacing: 12) {
                                    ForEach(Array(item.actions.enumerated()), id: \.offset) { _, action in
                                        if let title = actionTitle(action) {
                                            LineaOutlineButton(title: title) {
                                                Task { await intelligence.perform(action) }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func actionTitle(_ action: RecommendationAction) -> String? {
        switch action {
        case .markMealEaten: return "Поел"
        case .openTask: return "Открыть"
        case .deferTask: return "Перенести"
        case .acceptPlan, .dismiss: return nil
        }
    }

    // MARK: Greeting

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Доброе утро"
        case 12..<18: return "Добрый день"
        case 18..<23: return "Добрый вечер"
        default: return "Доброй ночи"
        }
    }

    private var dateSubtitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEE, d"
        return formatter.string(from: Date()).capitalizedFirst
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
