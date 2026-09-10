import Testing
import Foundation
@testable import LineaCore

@Suite("Детерминированные идентификаторы")
struct DeterministicIDTests {
    @Test("Один и тот же вход даёт один и тот же id")
    func stable() {
        #expect(DeterministicID.uuid(from: "plan|2026-09-09") == DeterministicID.uuid(from: "plan|2026-09-09"))
        #expect(DeterministicID.uuid(from: "plan|2026-09-09") != DeterministicID.uuid(from: "plan|2026-09-10"))
    }

    @Test("План дня не зависит от момента вызова")
    func planID() {
        let morning = DeterministicID.planID(day: WowFixture.today, time: WowFixture.morning)
        let afternoon = DeterministicID.planID(day: WowFixture.today, time: WowFixture.afternoon)
        #expect(morning == afternoon)
    }

    @Test("Ключ дня — локальная дата")
    func dayKey() {
        #expect(DeterministicID.dayKey(WowFixture.today, time: WowFixture.morning) == "2026-09-09")
    }

    @Test("Формат UUID корректен")
    func shape() {
        let id = DeterministicID.uuid(from: "linea")
        let text = id.uuidString
        #expect(text.count == 36)
        #expect(text.split(separator: "-").count == 5)
        #expect(text.split(separator: "-")[2].first == "4")
    }
}
