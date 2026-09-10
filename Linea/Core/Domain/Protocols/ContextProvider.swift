//
//  ContextProvider.swift
//  Linea
//
//  THE connector abstraction. HealthKit, tasks, calendar, nutrition — and
//  later Gmail, Location, Screen Time — all implement this and nothing else.
//  The ContextEngine calls every registered provider, tolerates failures and
//  timeouts, and merges the signals into a `ContextSnapshot`. Engines then
//  consume signal KINDS, so a new wearable that emits the same kinds needs no
//  engine change.
//
//  Providers are `nonisolated` on purpose: under the project's default
//  MainActor isolation a plain protocol would force every fetch onto the main
//  actor and serialise the task group that runs them.
//

import Foundation

nonisolated protocol ContextProvider: Sendable {
    /// Stable identity, e.g. `.healthKit`.
    var id: ProviderID { get }
    /// Shown on Profile → «Подключения».
    var displayName: String { get }
    /// Signal kinds this provider can emit (diagnostics, «Подключения»).
    var provides: Set<SignalKind> { get }
    /// Fetch signals for the request window. Throwing is allowed; the
    /// ContextEngine turns it into `ProviderStatus.failed`.
    func fetchContext(_ request: ContextRequest) async throws -> ProviderFetchResult
}
