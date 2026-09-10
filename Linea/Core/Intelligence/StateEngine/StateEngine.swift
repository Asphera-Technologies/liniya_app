//
//  StateEngine.swift
//  Linea
//
//  The State Engine entry point: runs every registered `StateAnalyzer` over
//  a `StateInput`, fuses their components into `UserState` and collects the
//  typed facts the narrator may use. Pure and deterministic — the same input
//  always yields the same state, which is what makes the wow-scenario a test.
//
//  Baselines are taken from the input when the use case already computed
//  them, otherwise derived here from the history with `BaselineCalculator`.
//

import Foundation

nonisolated struct StateEngine: Sendable {
    let analyzers: [any StateAnalyzer]
    let config: EngineConfig
    var baselineCalculator = BaselineCalculator()
    var seriesBuilder = DailySeriesBuilder()
    var fusion = EnergyFusion()

    /// Built-in analyzers in fusion order: sleep, recovery, strain.
    static var defaultAnalyzers: [any StateAnalyzer] {
        [SleepStateAnalyzer(), RecoveryStateAnalyzer(), StrainStateAnalyzer()]
    }

    /// `config` is the single configuration of an evaluation: it replaces
    /// `input.config` for the analyzers so fusion and analysis never disagree.
    init(analyzers: [any StateAnalyzer] = StateEngine.defaultAnalyzers, config: EngineConfig = .default) {
        self.analyzers = analyzers
        self.config = config
    }

    func evaluate(_ input: StateInput) -> UserState {
        let time = input.time
        let baselines = input.baselines ?? baselineCalculator.compute(history: input.history, config: config, time: time)
        let resolved = StateInput(
            snapshot: input.snapshot,
            baselines: baselines,
            history: input.history,
            calibration: input.calibration,
            config: config,
            time: time,
            previousLoadAdvice: input.previousLoadAdvice
        )

        let series = seriesBuilder.build(snapshot: resolved.snapshot, time: time)
        let components = analyzers.compactMap { $0.analyze(resolved) }

        let fused = fusion.fuse(components: components, config: config, calibration: resolved.calibration)
        let advice = fusion.loadAdvice(
            energy: fused.energy,
            confidence: fused.confidence,
            recoveryScore: components.first { $0.kind == .recovery }?.score,
            asleepSeconds: series.sleepNight?.asleepSeconds,
            previous: resolved.previousLoadAdvice,
            config: config,
            calibration: resolved.calibration
        )

        // Facts: components first, then the verdict, then the data situation.
        var facts: [Fact] = components.flatMap(\.facts)
        facts.append(.energy(value: fused.energy, confidence: fused.confidence))
        facts.append(.loadAdvice(advice))

        let progress = coldStartProgress(in: components)
        if let progress { facts.append(.coldStart(days: progress.days, needed: progress.needed)) }

        for provider in resolved.snapshot.providerStatuses.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            if let status = resolved.snapshot.providerStatuses[provider], !status.isHealthy {
                facts.append(.providerUnavailable(provider: provider, status: status))
            }
        }
        if series.sleepNight == nil { facts.append(.dataMissing(kind: .sleepSegment)) }
        if series.summary[.hrvLog] == nil { facts.append(.dataMissing(kind: .hrvSDNN)) }
        if series.summary[.restingHeartRate] == nil { facts.append(.dataMissing(kind: .restingHeartRate)) }

        return UserState(
            day: time.startOfDay(resolved.snapshot.day),
            computedAt: time.now,
            components: components,
            energy: fused.energy,
            confidence: fused.confidence,
            loadAdvice: advice,
            sleepNight: series.sleepNight,
            baselineProgress: progress,
            facts: deduplicated(facts)
        )
    }

    /// The least-complete baseline among components still collecting one.
    private func coldStartProgress(in components: [StateComponent]) -> BaselineProgress? {
        var progress: BaselineProgress?
        for fact in components.flatMap(\.facts) {
            guard case .coldStart(let days, let needed) = fact else { continue }
            if progress == nil || days < progress!.days {
                progress = BaselineProgress(days: days, needed: needed)
            }
        }
        return progress
    }

    private func deduplicated(_ facts: [Fact]) -> [Fact] {
        var seen = Set<Fact>()
        return facts.filter { seen.insert($0).inserted }
    }
}
