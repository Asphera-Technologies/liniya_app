//
//  UserState.swift
//  Linea
//
//  The output of the State Engine: how much the user has "in the tank" today,
//  built from independent components (sleep, recovery, strain, fuel…), each
//  with its own confidence. Components are an open list so a connector can add
//  one (e.g. nutrition → fuel) without changing the fusion formula.
//

import Foundation

/// Identifies a state component. Open — connectors add their own.
nonisolated struct StateComponentKind: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral, CodingKeyRepresentable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.rawValue = value }

    static let sleep: StateComponentKind = "sleep"
    static let recovery: StateComponentKind = "recovery"
    static let strain: StateComponentKind = "strain"
    static let fuel: StateComponentKind = "fuel"
}

/// Today vs. this user's usual.
nonisolated enum UsualLevel: String, Codable, Hashable, Sendable {
    case belowUsual, usual, aboveUsual, unknown
}

nonisolated struct StateComponent: Codable, Hashable, Sendable {
    let kind: StateComponentKind
    /// 0…1, 0.5 = neutral.
    let score: Double
    /// 0…1 — how much this component should be trusted today.
    let confidence: Double
    /// Weighted z vs baseline if available.
    let z: Double?
    let level: UsualLevel
    let facts: [Fact]

    init(kind: StateComponentKind, score: Double, confidence: Double, z: Double? = nil, level: UsualLevel = .unknown, facts: [Fact] = []) {
        self.kind = kind
        self.score = min(max(score, 0), 1)
        self.confidence = min(max(confidence, 0), 1)
        self.z = z
        self.level = level
        self.facts = facts
    }
}

nonisolated enum LoadAdvice: String, Codable, Hashable, Sendable {
    case reduce, normal, push, unknown
}

nonisolated struct UserState: Codable, Sendable {
    static let schemaVersion = 1

    let day: Date
    let computedAt: Date
    let components: [StateComponent]
    /// Fused daily energy 0…1 (before the circadian curve). 0.5 = unknown/neutral.
    let energy: Double
    /// 0…1 overall confidence of `energy`.
    let confidence: Double
    let loadAdvice: LoadAdvice
    /// Last night, if known.
    let sleepNight: SleepNight?
    /// Days of baseline collected vs needed (cold start), if a baseline is still forming.
    let baselineProgress: BaselineProgress?
    /// Everything the narrator may say, typed.
    let facts: [Fact]

    init(
        day: Date,
        computedAt: Date,
        components: [StateComponent],
        energy: Double,
        confidence: Double,
        loadAdvice: LoadAdvice,
        sleepNight: SleepNight? = nil,
        baselineProgress: BaselineProgress? = nil,
        facts: [Fact] = []
    ) {
        self.day = day
        self.computedAt = computedAt
        self.components = components
        self.energy = min(max(energy, 0), 1)
        self.confidence = min(max(confidence, 0), 1)
        self.loadAdvice = loadAdvice
        self.sleepNight = sleepNight
        self.baselineProgress = baselineProgress
        self.facts = facts
    }

    func component(_ kind: StateComponentKind) -> StateComponent? {
        components.first { $0.kind == kind }
    }

    /// A state that knows nothing (no health data at all).
    static func unknown(day: Date, computedAt: Date, facts: [Fact] = []) -> UserState {
        UserState(day: day, computedAt: computedAt, components: [], energy: 0.5, confidence: 0, loadAdvice: .unknown, facts: facts)
    }
}

nonisolated struct BaselineProgress: Codable, Hashable, Sendable {
    let days: Int
    let needed: Int
    var isComplete: Bool { days >= needed }
}
