//
//  LineaFont.swift
//  Linea
//
//  Typographic scale for the Linea design system.
//
//  Character: SF Pro, calm and light. Titles are large but *regular* weight
//  (never heavy). Section labels are small and quiet. Metric values are large
//  and airy. All tokens are style-relative so Dynamic Type keeps working.
//

import SwiftUI

enum LineaFont {

    /// The small "Linea" wordmark shown at the top of every screen.
    static let wordmark = Font.system(.subheadline, design: .default).weight(.semibold)

    /// Large screen title (e.g. "Добрый день", "План"). Regular weight = calm.
    static let largeTitle = Font.system(.largeTitle, design: .default).weight(.regular)

    /// Small, quiet gray section label (e.g. "Главное сегодня", "Цели").
    static let sectionLabel = Font.system(.subheadline, design: .default)

    /// A prominent single item under a section (e.g. the day's main task).
    static let feature = Font.system(.title2, design: .default).weight(.regular)

    /// Standard list-row title.
    static let rowTitle = Font.system(.body, design: .default)

    /// Trailing value / detail text on a list row.
    static let rowValue = Font.system(.body, design: .default)

    /// Large metric number (e.g. sleep duration, steps).
    static let metricValue = Font.system(.title, design: .default).weight(.regular)

    /// Small metric caption above a value.
    static let metricLabel = Font.system(.subheadline, design: .default)

    /// Text inside bordered buttons and segmented controls.
    static let control = Font.system(.callout, design: .default).weight(.medium)

    /// Small supporting caption (task meta, goal status).
    static let caption = Font.system(.footnote, design: .default)
}
