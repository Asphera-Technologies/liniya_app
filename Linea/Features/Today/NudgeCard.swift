//
//  NudgeCard.swift
//  Linea
//
//  The in-app form of a nudge: the same text and the same two answers the
//  notification offers, so the user sees one behaviour whether the app was
//  open or not. Text comes ready from the core — the card never composes it.
//

import SwiftUI

struct NudgeCard: View {
    let nudge: Nudge
    let onAction: (NudgeAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(nudge.title)
                .font(LineaFont.feature)
                .foregroundStyle(LineaColor.textPrimary)
            if !nudge.body.isEmpty {
                Text(nudge.body)
                    .font(LineaFont.rowTitle)
                    .foregroundStyle(LineaColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !nudge.actions.isEmpty {
                HStack(spacing: 12) {
                    ForEach(Array(nudge.actions.enumerated()), id: \.offset) { _, action in
                        LineaOutlineButton(title: action.title) { onAction(action) }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: LineaMetrics.surfaceRadius, style: .continuous)
                .strokeBorder(LineaColor.separator, lineWidth: LineaMetrics.hairline)
        )
        .accessibilityElement(children: .contain)
    }
}

/// Three taps at the end of the day — the whole evening feedback loop.
struct EveningReviewCard: View {
    let onRate: (DayRating) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Как прошёл день?")
                .font(LineaFont.feature)
                .foregroundStyle(LineaColor.textPrimary)
            HStack(spacing: 12) {
                ForEach(DayRating.allCases, id: \.self) { rating in
                    LineaOutlineButton(title: rating.title) { onRate(rating) }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: LineaMetrics.surfaceRadius, style: .continuous)
                .strokeBorder(LineaColor.separator, lineWidth: LineaMetrics.hairline)
        )
    }
}

/// One line of the day's timeline: time on the left, what happens on the right.
struct PlanBlockRow: View {
    let block: PlanBlock
    let time: TimeContext
    var isDone: Bool = false
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text(clock)
                    .font(LineaFont.rowTitle)
                    .foregroundStyle(LineaColor.textTertiary)
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.title)
                        .font(LineaFont.rowTitle)
                        .strikethrough(isDone, color: LineaColor.textTertiary)
                        .foregroundStyle(isDone ? LineaColor.textTertiary : LineaColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let detail {
                        Text(detail)
                            .font(LineaFont.caption)
                            .foregroundStyle(LineaColor.textTertiary)
                    }
                }
                Spacer(minLength: 0)
                if block.isTop {
                    Text("Главное")
                        .font(LineaFont.caption)
                        .foregroundStyle(LineaColor.textSecondary)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }

    private var clock: String {
        let start = time.timeOfDay(of: block.start)
        return String(format: "%d:%02d", start.hour, start.minute)
    }

    private var detail: String? {
        switch block.kind {
        case .focus:
            return "\(block.durationMinutes) мин"
        case .commitment, .meal, .rest:
            return nil
        }
    }
}
