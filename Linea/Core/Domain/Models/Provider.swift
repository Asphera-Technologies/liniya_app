//
//  Provider.swift
//  Linea
//
//  Value types shared by every `ContextProvider` (the connector abstraction).
//

import Foundation

/// What the ContextEngine asks a provider for.
nonisolated struct ContextRequest: Sendable {
    /// The local day being planned.
    let day: DateInterval
    /// Time context (now, calendar, locale) — providers must not read ambient time.
    let time: TimeContext
    /// How many days of history before `day` to include (0 = only the day itself).
    let historyDays: Int

    init(day: DateInterval, time: TimeContext, historyDays: Int = 0) {
        self.day = day
        self.time = time
        self.historyDays = historyDays
    }

    /// The whole window a provider should cover: history + the day itself.
    var window: DateInterval {
        let start = time.adding(days: -historyDays, to: day.start)
        return DateInterval(start: start, end: day.end)
    }
}

/// Health of a connector at capture time. Shown on Profile → «Подключения»
/// and used by engines to explain degraded output honestly.
nonisolated enum ProviderStatus: Codable, Hashable, Sendable {
    /// Signals were delivered.
    case ready
    /// Access granted (or unknown) but nothing to report for the window.
    case noData
    /// Cannot tell "denied" from "no data" (HealthKit hides read authorization).
    case indeterminate
    case unauthorized
    /// Not available on this device (e.g. no HealthKit on iPad).
    case unavailable
    case timedOut
    case failed(String)

    var isHealthy: Bool {
        switch self {
        case .ready, .noData: return true
        default: return false
        }
    }
}

/// What a provider returns: signals plus its own view of its status.
nonisolated struct ProviderFetchResult: Sendable {
    let signals: [ContextSignal]
    let status: ProviderStatus

    init(signals: [ContextSignal], status: ProviderStatus? = nil) {
        self.signals = signals
        self.status = status ?? (signals.isEmpty ? .noData : .ready)
    }

    static let empty = ProviderFetchResult(signals: [], status: .noData)
}

nonisolated enum ProviderError: Error, Sendable, Equatable {
    case unauthorized
    case unavailable
    case failed(String)
}
