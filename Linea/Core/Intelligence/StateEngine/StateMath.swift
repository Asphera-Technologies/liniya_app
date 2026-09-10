//
//  StateMath.swift
//  Linea
//
//  Small pure helpers shared by the State Engine: clamping, linear ramps,
//  robust statistics and interval unions. Kept in one place so every formula
//  in Docs/intelligence.md §6 reads the same way in code as on paper.
//

import Foundation

nonisolated enum StateMath {
    static func clamp(_ x: Double, _ lower: Double = 0, _ upper: Double = 1) -> Double {
        min(max(x, lower), upper)
    }

    /// `lin(x, x0, x1) = clamp((x − x0) / (x1 − x0), 0, 1)`; degenerate ranges step at `x0`.
    static func lin(_ x: Double, _ x0: Double, _ x1: Double) -> Double {
        guard x1 != x0 else { return x >= x0 ? 1 : 0 }
        return clamp((x - x0) / (x1 - x0))
    }

    /// Median of a non-empty array (mean of the two middle values for even counts).
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[mid] }
        return (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// Median absolute deviation around `center`.
    static func mad(_ values: [Double], center: Double) -> Double? {
        median(values.map { abs($0 - center) })
    }

    /// Merges overlapping or touching intervals; result is sorted by start.
    static func union(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in sorted {
            if let last = merged.last, interval.start <= last.end {
                if interval.end > last.end {
                    merged[merged.count - 1] = DateInterval(start: last.start, end: interval.end)
                }
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    static func totalDuration(_ intervals: [DateInterval]) -> TimeInterval {
        intervals.reduce(0) { $0 + $1.duration }
    }
}
