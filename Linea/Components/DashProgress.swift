//
//  DashProgress.swift
//  Linea
//
//  The segmented dash progress indicator used on goals: a row of short bars,
//  filled in ink up to the goal's progress and faded for the remainder.
//

import SwiftUI

struct DashProgress: View {
    /// Progress from 0...1.
    let progress: Double
    var segments: Int = 8

    private var filledCount: Int {
        let clamped = min(max(progress, 0), 1)
        return Int((clamped * Double(segments)).rounded())
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<segments, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index < filledCount ? LineaColor.ink : LineaColor.separator)
                    .frame(height: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Прогресс")
        .accessibilityValue("\(Int((min(max(progress, 0), 1)) * 100)) процентов")
    }
}
