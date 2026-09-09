//
//  MetricTile.swift
//  Linea
//
//  A single at-a-glance metric: a small gray caption above a large value.
//  Used in the 2-column grid on the Health screen.
//

import SwiftUI

struct MetricTile: View {
    let label: String
    let value: String
    /// When true, the value is shown dimmed (e.g. not yet connected / demo).
    var isPlaceholder: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(LineaFont.metricLabel)
                .foregroundStyle(LineaColor.textSecondary)
            Text(value)
                .font(LineaFont.metricValue)
                .foregroundStyle(isPlaceholder ? LineaColor.textTertiary : LineaColor.textPrimary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
