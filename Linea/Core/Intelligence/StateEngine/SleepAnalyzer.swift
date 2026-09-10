//
//  SleepAnalyzer.swift
//  Linea
//
//  Turns raw `.sleepSegment` signals into one `SleepNight` per night. The
//  hard part is not the arithmetic but the sources: Watch writes stages,
//  iPhone writes «in bed» for the same hours, and summing both doubles the
//  night. So segments are grouped by `sourceBundle`, ONE source is chosen
//  (stages win, then the longest asleep sum) and its intervals are unioned.
//
//  A night belongs to the day the user wakes up on: window
//  [D−1 18:00, D 12:00), a segment is assigned by its midpoint. Daytime naps
//  fall outside every window and are ignored in v1.
//

import Foundation

nonisolated struct SleepAnalyzer: Sendable {
    /// Local time on D−1 where the night window for day D opens.
    var nightStart = TimeOfDay(hour: 18)
    /// Local time on D where the night window closes.
    var nightEnd = TimeOfDay(hour: 12)
    /// A gap between asleep intervals longer than this counts as an awakening.
    var awakeningGapSeconds: TimeInterval = 5 * 60
    /// Estimated asleep share when a source reports only «in bed».
    var inBedOnlyAsleepShare: Double = 0.9

    init() {}

    // MARK: Windows

    /// The night window for `day` (the wake-up day).
    func nightWindow(for day: Date, time: TimeContext) -> DateInterval {
        let wakeDay = time.startOfDay(day)
        let start = time.date(on: time.adding(days: -1, to: wakeDay), at: nightStart)
        let end = time.date(on: wakeDay, at: nightEnd)
        return DateInterval(start: start, end: max(start, end))
    }

    /// The wake-up day whose night window contains `moment`, or nil for daytime.
    func nightDay(containing moment: Date, time: TimeContext) -> Date? {
        let day = time.startOfDay(moment)
        let local = time.timeOfDay(of: moment)
        if local >= nightStart { return time.adding(days: 1, to: day) }
        if local < nightEnd { return day }
        return nil
    }

    // MARK: Nights

    /// Last night for `day`, or nil when there are no usable segments.
    func night(for day: Date, signals: [ContextSignal], time: TimeContext) -> SleepNight? {
        let wakeDay = time.startOfDay(day)
        let segments = sleepSegments(signals).filter { nightDay(containing: $0.midpoint, time: time) == wakeDay }
        return buildNight(day: wakeDay, segments: segments, time: time)
    }

    /// Every night present in `signals`, oldest first.
    func nights(signals: [ContextSignal], time: TimeContext) -> [SleepNight] {
        var byDay: [Date: [Segment]] = [:]
        for segment in sleepSegments(signals) {
            guard let day = nightDay(containing: segment.midpoint, time: time) else { continue }
            byDay[day, default: []].append(segment)
        }
        return byDay.keys.sorted().compactMap { buildNight(day: $0, segments: byDay[$0] ?? [], time: time) }
    }

    // MARK: Internals

    private struct Segment {
        let interval: DateInterval
        let stage: SleepStage
        let sourceKey: String
        var midpoint: Date { interval.start.addingTimeInterval(interval.duration / 2) }
    }

    private func sleepSegments(_ signals: [ContextSignal]) -> [Segment] {
        signals.compactMap { signal in
            guard signal.kind == .sleepSegment, signal.duration > 0 else { return nil }
            // A segment without a stage attribute is still sleep (older sources write no stages).
            let stage = signal.attributes[SignalAttribute.stage].flatMap(SleepStage.init(rawValue:)) ?? .unspecified
            let key = signal.attributes[SignalAttribute.sourceBundle] ?? signal.source.rawValue
            return Segment(interval: signal.interval, stage: stage, sourceKey: key)
        }
    }

    private struct SourceGroup {
        let key: String
        let segments: [Segment]
        let asleep: [DateInterval]      // merged asleep intervals
        let inBed: [DateInterval]       // merged inBed intervals
        let hasStages: Bool
        var asleepSum: TimeInterval { StateMath.totalDuration(asleep) }
    }

    private func buildNight(day: Date, segments: [Segment], time: TimeContext) -> SleepNight? {
        guard !segments.isEmpty else { return nil }

        let groups: [SourceGroup] = Dictionary(grouping: segments, by: \.sourceKey).map { key, segs in
            SourceGroup(
                key: key,
                segments: segs,
                asleep: StateMath.union(segs.filter { $0.stage.isAsleep }.map(\.interval)),
                inBed: StateMath.union(segs.filter { $0.stage == .inBed }.map(\.interval)),
                hasStages: segs.contains { [.core, .deep, .rem].contains($0.stage) }
            )
        }
        .filter { !$0.asleep.isEmpty || !$0.inBed.isEmpty }

        // Stages first, then the longest asleep sum, then the name — fully deterministic.
        guard let source = groups.max(by: { a, b in
            if a.hasStages != b.hasStages { return !a.hasStages }
            if a.asleepSum != b.asleepSum { return a.asleepSum < b.asleepSum }
            return a.key > b.key
        }) else { return nil }

        if source.asleep.isEmpty {
            // Only «in bed» (iPhone without a Watch): estimate, and say so via quality.
            let inBedSeconds = StateMath.totalDuration(source.inBed)
            guard let first = source.inBed.first, let last = source.inBed.last else { return nil }
            return SleepNight(
                day: day,
                bedtime: first.start,
                wakeTime: last.end,
                asleepSeconds: inBedSeconds * inBedOnlyAsleepShare,
                inBedSeconds: inBedSeconds,
                stages: [:],
                quality: 0.5,
                sourceName: source.key,
                awakenings: awakenings(in: source.inBed)
            )
        }

        guard let first = source.asleep.first, let last = source.asleep.last else { return nil }
        let asleepSeconds = StateMath.totalDuration(source.asleep)
        let inBedSeconds: TimeInterval
        if source.inBed.isEmpty {
            let spanStart = source.segments.map(\.interval.start).min() ?? first.start
            let spanEnd = source.segments.map(\.interval.end).max() ?? last.end
            inBedSeconds = max(spanEnd.timeIntervalSince(spanStart), asleepSeconds)
        } else {
            inBedSeconds = max(StateMath.totalDuration(source.inBed), asleepSeconds)
        }

        var stages: [SleepStage: TimeInterval] = [:]
        if source.hasStages {
            for stage in SleepStage.allCases where stage != .inBed {
                let seconds = StateMath.totalDuration(StateMath.union(source.segments.filter { $0.stage == stage }.map(\.interval)))
                if seconds > 0 { stages[stage] = seconds }
            }
        }

        return SleepNight(
            day: day,
            bedtime: first.start,
            wakeTime: last.end,
            asleepSeconds: asleepSeconds,
            inBedSeconds: inBedSeconds,
            stages: stages,
            quality: source.hasStages ? 1.0 : 0.8,
            sourceName: source.key,
            awakenings: awakenings(in: source.asleep)
        )
    }

    private func awakenings(in merged: [DateInterval]) -> Int {
        guard merged.count > 1 else { return 0 }
        var count = 0
        for i in 1..<merged.count where merged[i].start.timeIntervalSince(merged[i - 1].end) > awakeningGapSeconds {
            count += 1
        }
        return count
    }
}
