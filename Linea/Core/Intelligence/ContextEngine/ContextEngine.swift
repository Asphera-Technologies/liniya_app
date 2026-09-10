//
//  ContextEngine.swift
//  Linea
//
//  Collects everything Linea knows right now into one frozen `ContextSnapshot`.
//  Providers run concurrently and independently: a source that fails, hangs or
//  has nothing to say must not stop the day from being planned. Its status is
//  recorded instead, so the app can say «не вижу данных о сне» honestly rather
//  than silently planning as if the data were there.
//
//  `capture` never throws for that reason.
//

import Foundation

nonisolated struct ContextEngine: Sendable {
    let providers: [any ContextProvider]
    let mapper: CommitmentMapper
    /// How long a single provider may take before it is skipped.
    let timeout: Duration

    init(providers: [any ContextProvider], mapper: CommitmentMapper = CommitmentMapper(), timeout: Duration = .seconds(5)) {
        self.providers = providers
        self.mapper = mapper
        self.timeout = timeout
    }

    /// `additionalProviders` are connectors whose data the caller has just
    /// loaded (the nutrition profile changes between refreshes, so its
    /// provider is built per capture instead of being registered once).
    func capture(
        request: ContextRequest,
        snapshotID: UUID,
        tasks: [LineaTask],
        goals: [LineaGoal],
        profile: UserProfile,
        nutrition: NutritionProfile?,
        meals: [MealLog],
        additionalProviders: [any ContextProvider] = []
    ) async -> ContextSnapshot {
        let allProviders = providers + additionalProviders
        let results = await withTaskGroup(of: (ProviderID, ProviderFetchResult).self) { group in
            for provider in allProviders {
                group.addTask {
                    (provider.id, await fetch(provider, request: request, timeout: timeout))
                }
            }
            var collected: [(ProviderID, ProviderFetchResult)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        var statuses: [ProviderID: ProviderStatus] = [:]
        var signals: [ContextSignal] = []
        var seen = Set<String>()
        for (id, result) in results {
            statuses[id] = result.status
            for signal in result.signals where seen.insert(signal.id).inserted {
                signals.append(signal)
            }
        }
        // Deterministic order: the task group finishes in an arbitrary one.
        signals.sort { lhs, rhs in
            if lhs.source.rawValue != rhs.source.rawValue { return lhs.source.rawValue < rhs.source.rawValue }
            if lhs.kind.rawValue != rhs.kind.rawValue { return lhs.kind.rawValue < rhs.kind.rawValue }
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.end != rhs.end { return lhs.end < rhs.end }
            return lhs.id < rhs.id
        }

        return ContextSnapshot(
            id: snapshotID,
            day: request.day.start,
            capturedAt: request.time.now,
            timeZoneIdentifier: request.time.timeZone.identifier,
            signals: signals,
            providerStatuses: statuses,
            tasks: tasks,
            goals: goals,
            commitments: mapper.commitments(signals: signals, tasks: tasks, day: request.day, time: request.time),
            profile: profile,
            nutrition: nutrition,
            meals: meals
        )
    }
}

/// Runs one provider under a timeout, turning every failure into a status.
private func fetch(
    _ provider: any ContextProvider,
    request: ContextRequest,
    timeout: Duration
) async -> ProviderFetchResult {
    do {
        return try await withThrowingTaskGroup(of: ProviderFetchResult?.self) { group in
            group.addTask { try await provider.fetchContext(request) }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            // The first task to finish wins; the loser is cancelled.
            let winner = try await group.next() ?? nil
            group.cancelAll()
            guard let winner else { return ProviderFetchResult(signals: [], status: .timedOut) }
            return winner
        }
    } catch let error as ProviderError {
        switch error {
        case .unauthorized: return ProviderFetchResult(signals: [], status: .unauthorized)
        case .unavailable: return ProviderFetchResult(signals: [], status: .unavailable)
        case .failed(let message): return ProviderFetchResult(signals: [], status: .failed(message))
        }
    } catch is CancellationError {
        return ProviderFetchResult(signals: [], status: .timedOut)
    } catch {
        return ProviderFetchResult(signals: [], status: .failed(String(describing: error)))
    }
}
