import Testing
import Foundation
@testable import LineaCore

/// Срок ожидания источника держится, даже если источник не отвечает вовсе и
/// отмену не слышит — как Apple Health на только что загруженном симуляторе,
/// из-за которого «Сегодня» осталось без плана.
@Suite("Срок ожидания источника")
struct DeadlineTests {
    /// Никогда не отвечает и отмену не слышит.
    private static func never() async -> Int {
        await withUnsafeContinuation { (_: UnsafeContinuation<Int, Never>) in }
    }

    @Test("Успело — ответ работы")
    func answered() async throws {
        #expect(try await withDeadline(.seconds(5)) { 42 } == 42)
    }

    @Test("Ошибка работы — она же")
    func failure() async {
        await #expect(throws: ProviderError.unauthorized) {
            try await withDeadline(.seconds(5)) { () async throws -> Int in throw ProviderError.unauthorized }
        }
    }

    @Test("Не ответило и отмену не слышит — срок всё равно держится")
    func hanging() async {
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: DeadlineExceeded.self) {
            try await withDeadline(.milliseconds(100)) { await Self.never() }
        }
        #expect(clock.now - start < .seconds(5))
    }

    @Test("Отменили того, кто ждёт, — отмена, не ожидание до срока")
    func cancelled() async {
        let clock = ContinuousClock()
        let start = clock.now
        let waiting = Task { try await withDeadline(.seconds(60)) { await Self.never() } }
        waiting.cancel()
        await #expect(throws: CancellationError.self) { try await waiting.value }
        #expect(clock.now - start < .seconds(5))
    }
}
