//
//  LineaColor.swift
//  Linea
//
//  Core color tokens for the Linea design system.
//
//  Linea is near-monochrome and calm: a warm off-white canvas, near-black
//  ink for primary content, and layered grays for hierarchy. There is no
//  chromatic accent — emphasis comes from ink itself (selected controls,
//  completed markers). All tokens adapt to Dark Mode.
//

import SwiftUI
import UIKit

enum LineaColor {

    /// The primary app canvas — a warm off-white in light mode.
    static let background = dynamic(
        light: UIColor(red: 0.984, green: 0.984, blue: 0.980, alpha: 1),
        dark: UIColor(red: 0.043, green: 0.043, blue: 0.047, alpha: 1)
    )

    /// A subtly raised fill, used for segmented-control tracks and chips.
    static let fill = dynamic(
        light: UIColor(red: 0.941, green: 0.941, blue: 0.937, alpha: 1),
        dark: UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1)
    )

    /// Primary content color (titles, values, body).
    static let textPrimary = dynamic(
        light: UIColor(red: 0.067, green: 0.067, blue: 0.078, alpha: 1),
        dark: UIColor(red: 0.961, green: 0.961, blue: 0.965, alpha: 1)
    )

    /// Secondary content — section labels, supporting text.
    static let textSecondary = dynamic(
        light: UIColor(red: 0.608, green: 0.608, blue: 0.631, alpha: 1),
        dark: UIColor(red: 0.560, green: 0.560, blue: 0.588, alpha: 1)
    )

    /// Tertiary content — placeholders, values, chevrons, faded hints.
    static let textTertiary = dynamic(
        light: UIColor(red: 0.761, green: 0.761, blue: 0.784, alpha: 1),
        dark: UIColor(red: 0.400, green: 0.400, blue: 0.427, alpha: 1)
    )

    /// Hairline dividers.
    static let separator = dynamic(
        light: UIColor(red: 0.925, green: 0.925, blue: 0.918, alpha: 1),
        dark: UIColor(red: 0.161, green: 0.161, blue: 0.173, alpha: 1)
    )

    /// The ink accent — used for selected states and completed markers.
    /// Deliberately the same as primary text: Linea's "brand color" is ink.
    static let ink = textPrimary

    /// Foreground color to place on top of `ink` (e.g. selected pill text).
    static let onInk = background

    // MARK: - Helpers

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}
