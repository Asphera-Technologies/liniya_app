//
//  Deadline.swift
//  Linea
//
//  Ждать источник данных не дольше срока. Группа задач со спящим «таймером»
//  срок не держит: она дожидается всех своих задач, и источник, который не
//  отвечает и не слышит отмену, держит её вечно. Так Apple Health на только что
//  загруженном симуляторе оставил «Сегодня» без плана: первый пересчёт дня его
//  ждал, а все следующие ждали первый. Здесь ответ приходит к сроку в любом
//  случае; работа отменяется и, если отмену не слышит, заканчивается впустую.
//

import Foundation

/// Срок вышел, а ответа нет.
nonisolated struct DeadlineExceeded: Error, Sendable {}

/// Результат `operation`, если он пришёл за `limit`, иначе — `DeadlineExceeded`.
/// Ошибка работы — она же; отменили того, кто ждёт, — `CancellationError`.
nonisolated func withDeadline<T: Sendable>(
    _ limit: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let race = DeadlineRace<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            race.start(continuation, limit: limit, operation: operation)
        }
    } onCancel: {
        race.finish(.failure(CancellationError()))
    }
}

/// Работа и срок наперегонки: кто первый, тот и отвечает, второй — впустую.
private nonisolated final class DeadlineRace<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?
    private var isFinished = false
    private var runners: [Task<Void, Never>] = []

    func start(
        _ continuation: CheckedContinuation<T, any Error>,
        limit: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) {
        let cancelledEarlier = lock.withLock {
            if !isFinished { self.continuation = continuation }
            return isFinished
        }
        guard !cancelledEarlier else {
            continuation.resume(throwing: CancellationError())
            return
        }
        let work = Task {
            do { self.finish(.success(try await operation())) } catch { self.finish(.failure(error)) }
        }
        let timer = Task {
            try? await Task.sleep(for: limit)
            self.finish(.failure(DeadlineExceeded()))
        }
        let finishedMeanwhile = lock.withLock {
            if !isFinished { runners = [work, timer] }
            return isFinished
        }
        if finishedMeanwhile {
            work.cancel()
            timer.cancel()
        }
    }

    func finish(_ result: Result<T, any Error>) {
        let (continuation, runners) = lock.withLock { () -> (CheckedContinuation<T, any Error>?, [Task<Void, Never>]) in
            guard !isFinished else { return (nil, []) }
            isFinished = true
            defer {
                self.continuation = nil
                self.runners = []
            }
            return (self.continuation, self.runners)
        }
        runners.forEach { $0.cancel() }
        continuation?.resume(with: result)
    }
}
