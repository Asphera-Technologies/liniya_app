//
//  Circadian.swift
//  Linea
//
//  A chronotype-neutral alertness prior over the local hour: a morning peak,
//  a post-lunch dip and a smaller late-afternoon peak. Scaled by daily energy
//  it becomes the "capacity" a task's cognitive demand is matched against —
//  a bad night lowers the whole curve but never zeroes the morning.
//

import Foundation

nonisolated enum Circadian {
    /// (hour, alertness) nodes; linear interpolation in between, flat outside.
    static let nodes: [(hour: Double, alertness: Double)] = [
        (6, 0.45), (7, 0.55), (8, 0.70), (9, 0.85), (10, 0.95), (11, 1.00),
        (12, 0.90), (13, 0.75), (14, 0.65), (15, 0.70), (16, 0.80), (17, 0.85),
        (18, 0.80), (19, 0.70), (20, 0.60), (21, 0.50), (22, 0.40), (23, 0.30),
    ]

    /// Alertness 0…1 at a local hour fraction (14.5 = 14:30).
    static func alertness(atHour hour: Double) -> Double {
        guard let first = nodes.first, let last = nodes.last else { return 0.7 }
        if hour <= first.hour { return first.alertness }
        if hour >= last.hour { return last.alertness }
        for i in 1..<nodes.count {
            let a = nodes[i - 1], b = nodes[i]
            if hour <= b.hour {
                let t = (hour - a.hour) / (b.hour - a.hour)
                return a.alertness + (b.alertness - a.alertness) * t
            }
        }
        return last.alertness
    }

    static func alertness(at date: Date, time: TimeContext) -> Double {
        alertness(atHour: time.hourFraction(of: date))
    }

    /// Capacity available for work at a moment: energy scales the curve into 0.5…1.0
    /// so that poor sleep lowers but does not erase the morning peak.
    static func capacity(energy: Double, at date: Date, time: TimeContext) -> Double {
        let scale = 0.5 + 0.5 * min(max(energy, 0), 1)
        return scale * alertness(at: date, time: time)
    }
}
