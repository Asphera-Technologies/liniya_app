import Testing
import Foundation
@testable import LineaCore

@Suite("Итог дня: разбор правилами")
struct RuleBasedCheckInExtractorTests {

    @Test("Сценарий вечера: задачи, сверх плана, объём, оценка, память")
    func wowEvening() throws {
        let extraction = CheckInFixture.parse(CheckInFixture.transcript)

        #expect(CheckInFixture.status(of: WowFixture.taskA, in: extraction) == .done)
        #expect(CheckInFixture.status(of: WowFixture.taskC, in: extraction) == .done)
        #expect(CheckInFixture.status(of: WowFixture.taskCall, in: extraction) == .done)
        #expect(CheckInFixture.status(of: WowFixture.taskB, in: extraction) == .partial)
        #expect(CheckInFixture.status(of: WowFixture.taskWorkout, in: extraction) == .notDone)
        #expect(extraction.outcomes.allSatisfy { $0.isConfident })

        #expect(extraction.extra == [ExtraWork(title: "Созвонился с поставщиком", minutes: 40)])
        #expect(extraction.statedWorkMinutes == 420)
        #expect(extraction.rating == .hard)
        #expect(extraction.energy == .low)
        #expect(extraction.summary == nil)
        #expect(extraction.extractorID == "rules")

        let fact = try #require(extraction.memory.first)
        #expect(fact.text == "После обеда я плохо соображаю")
        #expect(fact.isExplicit)
        #expect(fact.kind == .pattern)
    }

    @Test("«Сделал отчёт и презентацию» — вторая задача наследует «сделал»")
    func inheritance() {
        let tasks = [
            LineaTask(id: WowFixture.taskA, title: "Отчёт", date: WowFixture.today),
            LineaTask(id: WowFixture.taskB, title: "Презентация", date: WowFixture.today),
            LineaTask(id: WowFixture.taskC, title: "Спортзал", date: WowFixture.today),
        ]
        let extraction = CheckInFixture.parse("Сделал отчёт и презентацию, а спортзал не успел.", tasks: tasks)
        #expect(CheckInFixture.status(of: WowFixture.taskA, in: extraction) == .done)
        #expect(CheckInFixture.status(of: WowFixture.taskB, in: extraction) == .done)
        #expect(CheckInFixture.status(of: WowFixture.taskC, in: extraction) == .notDone)
    }

    @Test("Упомянул без глагола — задача не отмечается сама")
    func mentionedOnly() throws {
        let extraction = CheckInFixture.parse("Утром была презентация КП.")
        let outcome = try #require(extraction.outcome(for: WowFixture.taskA))
        #expect(outcome.isConfident == false)
    }

    @Test("Глагол из названия — тоже свидетельство: «ответил на письма»")
    func titleVerb() {
        let extraction = CheckInFixture.parse("Ответил на письма.")
        #expect(extraction.outcome(for: WowFixture.taskC) == TaskOutcome(taskID: WowFixture.taskC, status: .done))
        // А просто «ответить на письма» — не сделано.
        let listing = CheckInFixture.parse("Завтра надо ответить на письма.")
        #expect(listing.outcome(for: WowFixture.taskC)?.status != .done || listing.outcome(for: WowFixture.taskC)?.isConfident == false)
    }

    @Test("Частичное совпадение названия не перебивает полное")
    func partialMatchLoses() {
        let extraction = CheckInFixture.parse("Созвон с командой провели. Созвон с поставщиком перенесли.")
        #expect(extraction.outcome(for: WowFixture.taskCall) == TaskOutcome(taskID: WowFixture.taskCall, status: .done))
    }

    @Test("«Всё успел» и «ничего не успел» — про задачи дня")
    func globalStatements() {
        let all = CheckInFixture.parse("Всё сделал, день отличный.")
        #expect(all.outcomes.count == WowFixture.tasks.count)
        #expect(all.outcomes.allSatisfy { $0.status == .done })
        #expect(all.extra.isEmpty)

        let none = CheckInFixture.parse("Ничего не успел, весь день болела голова.")
        #expect(none.outcomes.allSatisfy { $0.status == .notDone })

        // Про конкретную задачу сказано отдельно — это главнее общего.
        let mixed = CheckInFixture.parse("Тренировку пропустил. Остальное всё сделал.")
        #expect(CheckInFixture.status(of: WowFixture.taskWorkout, in: mixed) == .notDone)
        #expect(CheckInFixture.status(of: WowFixture.taskA, in: mixed) == .done)
    }

    @Test("Объём: «всего» главнее отдельных кусков")
    func totalWork() {
        let pieces = CheckInFixture.parse("Поработал над отчётом два часа, потом ещё полтора часа работал над кодом.")
        #expect(pieces.statedWorkMinutes == 210)
        let total = CheckInFixture.parse("Над отчётом два часа, всего часов шесть.")
        #expect(total.statedWorkMinutes == 360)
        let none = CheckInFixture.parse("Сделал отчёт.")
        #expect(none.statedWorkMinutes == nil)
    }

    @Test("Пустой рассказ — пустой разбор, без падений")
    func empty() {
        let extraction = CheckInFixture.parse("   ")
        #expect(extraction.outcomes.isEmpty)
        #expect(extraction.extra.isEmpty)
        #expect(extraction.rating == nil)
        #expect(extraction.memory.isEmpty)
    }

    @Test("Какие задачи спрашивать вечером: день, закрытые сегодня, просроченные, немного без дня")
    func relevantTasks() {
        let time = WowFixture.evening
        let overdue = LineaTask(title: "Налоги", date: WowFixture.moment(0, 0, dayOffset: -3), createdAt: WowFixture.created)
        let tomorrow = LineaTask(title: "Завтрашнее", date: WowFixture.moment(0, 0, dayOffset: 1), createdAt: WowFixture.created)
        let closedToday = LineaTask(title: "Старое", date: WowFixture.moment(0, 0, dayOffset: 2), isDone: true,
                                    createdAt: WowFixture.created, completedAt: WowFixture.moment(19))
        let undated = LineaTask(title: "Когда-нибудь", createdAt: WowFixture.created)
        let tasks = WowFixture.tasks + [overdue, tomorrow, closedToday, undated]

        let relevant = CheckInRequest.relevantTasks(from: tasks, day: WowFixture.today, time: time)
        #expect(relevant.prefix(5).map(\.id) == WowFixture.tasks.map(\.id))
        #expect(relevant.contains(overdue))
        #expect(relevant.contains(closedToday))
        #expect(relevant.contains(undated))
        #expect(!relevant.contains(tomorrow))
    }
}
