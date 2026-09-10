//
//  HealthKitContextProvider.swift
//  Linea
//
//  The Apple Health connector: turns HealthKit into `ContextSignal`s for the
//  intelligence core. It is the only thing the core knows about health data —
//  swap it for another wearable's provider emitting the same signal kinds and
//  no engine changes.
//
//  Status is deliberately `.indeterminate` when nothing comes back: HealthKit
//  never reveals whether a read was denied or the user simply has no samples,
//  and the app must not accuse the user of either (same rule as `MetricState`).
//

import Foundation
import HealthKit

nonisolated final class HealthKitContextProvider: ContextProvider {
    let id: ProviderID = .healthKit
    let displayName = "Apple Health"
    let provides: Set<SignalKind> = [
        .sleepSegment, .hrvSDNN, .restingHeartRate, .steps, .activeEnergy, .workout,
    ]

    private let reader: HealthKitHistoryReader

    init(reader: HealthKitHistoryReader) {
        self.reader = reader
    }

    convenience init(store: HKHealthStore) {
        self.init(reader: HealthKitHistoryReader(store: store))
    }

    func fetchContext(_ request: ContextRequest) async throws -> ProviderFetchResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            return ProviderFetchResult(signals: [], status: .unavailable)
        }
        // Last night starts the previous evening, so the day window is widened.
        let window = DateInterval(
            start: request.time.adding(days: -1, to: request.window.start),
            end: request.window.end
        )
        let signals = try await reader.signals(in: window, time: request.time)
        return ProviderFetchResult(signals: signals, status: signals.isEmpty ? .indeterminate : .ready)
    }
}
