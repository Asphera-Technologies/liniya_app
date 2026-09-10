//
//  Signal.swift
//  Linea
//
//  The universal unit of context. Every connector (HealthKit, tasks, calendar,
//  nutrition, later Gmail/Location/Screen Time) turns what it knows into
//  `ContextSignal`s; engines subscribe to signal KINDS, never to providers.
//
//  `SignalKind` is string-backed and open: a connector declares its own kinds
//  in an `extension SignalKind` inside its own file, so adding a source never
//  touches the core.
//

import Foundation

/// Identifies what a signal measures, e.g. "health.sleep.segment".
nonisolated struct SignalKind: RawRepresentable, Hashable, Codable, Sendable,
                                ExpressibleByStringLiteral, CodingKeyRepresentable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.rawValue = value }

    var description: String { rawValue }

    /// Dot-separated namespace, e.g. "health" for "health.sleep.segment".
    var namespace: String { rawValue.split(separator: ".").first.map(String.init) ?? rawValue }
}

/// Core signal kinds consumed by the built-in engines.
nonisolated extension SignalKind {
    // Health (values from Apple Health; all read-only)
    /// A sleep segment: interval + `stage` attribute (inBed/core/deep/rem/unspecified/awake).
    static let sleepSegment: SignalKind = "health.sleep.segment"
    /// Heart-rate variability (SDNN), milliseconds; instantaneous sample.
    static let hrvSDNN: SignalKind = "health.hrv.sdnn"
    /// Resting heart rate, bpm; one per day.
    static let restingHeartRate: SignalKind = "health.heartRate.resting"
    /// Latest heart rate, bpm.
    static let heartRate: SignalKind = "health.heartRate.latest"
    /// Steps, count; cumulative for the interval.
    static let steps: SignalKind = "health.steps"
    /// Active energy, kilocalories; cumulative for the interval.
    static let activeEnergy: SignalKind = "health.activeEnergy"
    /// A completed workout: interval + `activity` attribute, value = kilocalories if known.
    static let workout: SignalKind = "health.workout"

    // Time
    /// Something that blocks time (meeting, meal window, planned workout, task with a fixed start).
    /// Interval + `label`; the ContextEngine turns these into `Commitment`s.
    static let commitment: SignalKind = "time.commitment"
}

/// Identifies the connector that produced a signal.
nonisolated struct ProviderID: RawRepresentable, Hashable, Codable, Sendable,
                                ExpressibleByStringLiteral, CodingKeyRepresentable, CustomStringConvertible {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.rawValue = value }
    var description: String { rawValue }

    static let healthKit: ProviderID = "healthKit"
    static let tasks: ProviderID = "tasks"
    static let nutrition: ProviderID = "nutrition"
    static let calendar: ProviderID = "calendar"
    static let fixture: ProviderID = "fixture"
}

/// The payload of a signal.
nonisolated enum SignalValue: Codable, Hashable, Sendable {
    /// A measurement; unit is carried in `ContextSignal.unit`.
    case number(Double)
    /// The signal IS its interval (sleep segment, commitment, workout); optional numeric payload.
    case interval(Double?)
    case text(String)
    case tags([String])

    var number: Double? {
        switch self {
        case .number(let v): return v
        case .interval(let v): return v
        default: return nil
        }
    }
}

nonisolated struct ContextSignal: Codable, Hashable, Sendable, Identifiable {
    let kind: SignalKind
    let value: SignalValue
    /// Start of the observation; equals `end` for instantaneous samples.
    let start: Date
    let end: Date
    let source: ProviderID
    /// Unit for numeric values ("s", "ms", "bpm", "count", "kcal", "min").
    let unit: String?
    /// 0…1. 1 = measured by a trusted sensor; lower for estimated/user-reported.
    let quality: Double
    /// Free-form details a connector wants to pass along (stage, activity, label, sourceBundle…).
    let attributes: [String: String]

    init(
        kind: SignalKind,
        value: SignalValue,
        start: Date,
        end: Date? = nil,
        source: ProviderID,
        unit: String? = nil,
        quality: Double = 1,
        attributes: [String: String] = [:]
    ) {
        self.kind = kind
        self.value = value
        self.start = start
        self.end = end ?? start
        self.source = source
        self.unit = unit
        self.quality = min(max(quality, 0), 1)
        self.attributes = attributes
    }

    /// Deterministic identity: same source + kind + time + value → same signal.
    var id: String { "\(source.rawValue)|\(kind.rawValue)|\(start.timeIntervalSince1970)|\(end.timeIntervalSince1970)|\(attributes["label"] ?? "")" }

    var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// Well-known attribute keys, so connectors and engines agree on spelling.
nonisolated enum SignalAttribute {
    static let stage = "stage"            // sleep: inBed | core | deep | rem | unspecified | awake
    static let sourceBundle = "sourceBundle"
    static let activity = "activity"      // workout display name
    static let label = "label"            // commitment title
    static let blocksTime = "blocksTime"  // "true"/"false" for commitments
    static let commitmentKind = "commitmentKind" // meeting | meal | workout | task | other
    static let taskID = "taskID"
    static let eventID = "eventID"
}

/// Sleep stages as written by HealthKit (`HKCategoryValueSleepAnalysis`), mapped to strings by the provider.
nonisolated enum SleepStage: String, Codable, Hashable, Sendable, CaseIterable {
    case inBed, awake, core, deep, rem, unspecified

    /// Stages that count as being asleep.
    var isAsleep: Bool {
        switch self {
        case .core, .deep, .rem, .unspecified: return true
        case .inBed, .awake: return false
        }
    }
}
