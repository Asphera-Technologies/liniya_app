//
//  LineaMetrics.swift
//  Linea
//
//  Spacing, sizing, and radius tokens. Linea's spacing philosophy is
//  generous and quiet: wide horizontal margins, large gaps between sections,
//  comfortable row heights, and flat surfaces separated by hairlines rather
//  than cards and shadows.
//

import CoreGraphics

enum LineaMetrics {

    /// Horizontal screen margin.
    static let screenPadding: CGFloat = 20

    /// Vertical gap between major sections.
    static let sectionSpacing: CGFloat = 32

    /// Gap between the wordmark and the large title.
    static let headerSpacing: CGFloat = 18

    /// Vertical padding inside a standard list row.
    static let rowVerticalPadding: CGFloat = 16

    /// Corner radius for controls (buttons, segmented tracks, command bar).
    static let controlRadius: CGFloat = 14

    /// Corner radius for larger surfaces.
    static let surfaceRadius: CGFloat = 16

    /// Standard tappable control height.
    static let controlHeight: CGFloat = 52

    /// Hairline thickness.
    static let hairline: CGFloat = 1
}
