//
//  SleepWeekChart.swift
//  Linea
//
//  A week of sleep as plain bars against the user's own norm. Deliberately not
//  a chart library: Linea is near-monochrome and flat, and one hairline for
//  «обычно» says more than axes and gridlines would.
//

import SwiftUI

struct SleepWeekChart: View {
    let nights: [SleepInsight.DailyNight]
    let usualSeconds: TimeInterval?

    private var maxSeconds: TimeInterval {
        max(nights.map(\.asleepSeconds).max() ?? 0, usualSeconds ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .bottomLeading) {
                    if let usualSeconds {
                        let y = geometry.size.height * (1 - usualSeconds / maxSeconds)
                        Rectangle()
                            .fill(LineaColor.separator)
                            .frame(height: LineaMetrics.hairline)
                            .offset(y: y)
                    }
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(nights, id: \.day) { night in
                            let ratio = night.asleepSeconds / maxSeconds
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(isBelow(night) ? LineaColor.textTertiary : LineaColor.ink)
                                .frame(height: max(2, geometry.size.height * ratio))
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel(label(for: night))
                        }
                    }
                }
            }
            .frame(height: 84)

            HStack(spacing: 6) {
                ForEach(nights, id: \.day) { night in
                    Text(weekday(night.day))
                        .font(LineaFont.caption)
                        .foregroundStyle(LineaColor.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func isBelow(_ night: SleepInsight.DailyNight) -> Bool {
        guard let usualSeconds else { return false }
        return night.asleepSeconds < usualSeconds * 0.95
    }

    private func label(for night: SleepInsight.DailyNight) -> String {
        "\(weekday(night.day)): \(HealthFormat.sleep(night.asleepSeconds))"
    }

    private func weekday(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEEEE"
        return formatter.string(from: day)
    }
}
