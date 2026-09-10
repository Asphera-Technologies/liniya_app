import Testing
import Foundation
@testable import LineaCore

@Suite("Подсказка связи задачи с целью")
struct KeywordGoalMatcherTests {
    private let matcher = KeywordGoalMatcher()

    private func goal(_ title: String, id: UUID = UUID(uuidString: "11111111-0000-0000-0000-000000000001")!, active: Bool = true) -> LineaGoal {
        LineaGoal(id: id, title: title, createdAt: WowFixture.created, isActive: active)
    }

    @Test("Задача из цели узнаётся по общим словам")
    func matchesByWords() {
        let goals = [goal("Запустить MVP Linea")]
        let match = matcher.bestMatch(for: "Разработка Linea: MVP", in: goals)
        #expect(match != nil)
        #expect(match!.score >= 0.2)
    }

    @Test("Морфология переживается обрезкой основы")
    func matchesDifferentForms() {
        let goals = [goal("Запустить MVP Linea")]
        #expect(matcher.bestMatch(for: "Запуск Linea в проде", in: goals) != nil)
    }

    @Test("Ничего общего — подсказки нет")
    func noMatch() {
        let goals = [goal("Запустить MVP Linea")]
        #expect(matcher.bestMatch(for: "Купить молоко", in: goals) == nil)
    }

    @Test("Неактивные и выполненные цели не предлагаются")
    func skipsInactive() {
        #expect(matcher.bestMatch(for: "Запуск Linea", in: [goal("Запустить MVP Linea", active: false)]) == nil)
        var completed = goal("Запустить MVP Linea")
        completed.isCompleted = true
        #expect(matcher.bestMatch(for: "Запуск Linea", in: [completed]) == nil)
    }

    @Test("Короткие слова не считаются значимыми")
    func ignoresShortWords() {
        #expect(matcher.stems(of: "и на в MVP Linea") == ["linea"])
    }

    @Test("Выбор лучшей цели детерминирован")
    func deterministic() {
        let a = goal("Запустить MVP Linea", id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-00000000000A")!)
        let b = goal("Запустить MVP Linea", id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-00000000000B")!)
        let first = matcher.bestMatch(for: "Запуск MVP Linea", in: [a, b])
        let second = matcher.bestMatch(for: "Запуск MVP Linea", in: [b, a])
        #expect(first?.goalID == second?.goalID)
        #expect(first?.goalID == a.id)
    }
}
