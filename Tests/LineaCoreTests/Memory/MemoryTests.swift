import Testing
import Foundation
@testable import LineaCore

@Suite("Память: «запомни»")
struct MemoryCommandTests {

    @Test("Просьба запомнить — в любом месте предложения")
    func triggers() {
        #expect(MemoryCommand.candidates(in: "Запомни, что по вторникам у меня зал в 19:00.").map(\.text) == ["По вторникам у меня зал в 19:00"])
        #expect(MemoryCommand.candidates(in: "По утрам я работаю лучше всего, учти.").map(\.text) == ["По утрам я работаю лучше всего"])
        #expect(MemoryCommand.candidates(in: "Имей в виду: после 20:00 я не работаю.").map(\.text) == ["После 20:00 я не работаю"])
        #expect(MemoryCommand.candidates(in: "Я запомнил, где лежат ключи.").isEmpty)
        #expect(MemoryCommand.candidates(in: "Запомни.").isEmpty)
    }

    @Test("Вид факта угадывается по словам")
    func kinds() {
        #expect(MemoryCommand.kind(of: "После 20:00 я не работаю") == .constraint)
        #expect(MemoryCommand.kind(of: "По вторникам зал") == .pattern)
        #expect(MemoryCommand.kind(of: "Люблю работать утром") == .preference)
        #expect(MemoryCommand.kind(of: "Готовлюсь к марафону") == .context)
    }

    @Test("Сообщение в чате целиком — просьба")
    func chatCommand() {
        #expect(MemoryCommand.command(in: "запомни: я не пью кофе после обеда")?.text == "Я не пью кофе после обеда")
        #expect(MemoryCommand.command(in: "Как мой сон?") == nil)
    }
}

@Suite("Память: консолидация")
struct MemoryConsolidatorTests {
    private let consolidator = MemoryConsolidator()
    private let time = WowFixture.evening

    @Test("Похожий факт не дублируется, а подтверждается")
    func reinforce() throws {
        let first = consolidator.merge([MemoryCandidate(text: "После обеда проседает концентрация", kind: .pattern)],
                                       into: .empty, source: .checkIn(day: WowFixture.today), time: time)
        let later = WowFixture.time(21, 0, dayOffset: 3)
        let second = consolidator.merge([MemoryCandidate(text: "Концентрация проседает после обеда", kind: .pattern)],
                                        into: first.memory, source: .checkIn(day: later.today), time: later)
        #expect(second.memory.facts.count == 1)
        let fact = try #require(second.memory.facts.first)
        #expect(fact.confirmations == 2)
        #expect(fact.lastConfirmedAt == later.now)
        #expect(second.added.isEmpty)
        #expect(second.confirmed.count == 1)
    }

    @Test("Явная просьба закрепляет факт и заменяет формулировку модели")
    func explicitPins() throws {
        let guessed = consolidator.merge([MemoryCandidate(text: "Любит работать утром", kind: .preference)],
                                         into: .empty, source: .checkIn(day: WowFixture.today), time: time)
        let asked = consolidator.merge([MemoryCandidate(text: "Люблю работать утром", kind: .preference, isExplicit: true)],
                                       into: guessed.memory, source: .chat, time: time)
        let fact = try #require(asked.memory.facts.first)
        #expect(asked.memory.facts.count == 1)
        #expect(fact.isPinned)
        #expect(fact.text == "Люблю работать утром")
        #expect(fact.confirmations == 2)
    }

    @Test("Разовое и давнее забывается, подтверждённое и закреплённое — нет")
    func forgetting() {
        let old = WowFixture.moment(12, 0, dayOffset: -90)
        let memory = UserMemory(facts: [
            MemoryFact(id: DeterministicID.uuid(from: "a"), text: "Раз упомянул йогу", kind: .context, source: .chat, createdAt: old),
            MemoryFact(id: DeterministicID.uuid(from: "b"), text: "Часто работает ночью", kind: .pattern, source: .chat, createdAt: old, confirmations: 3),
            MemoryFact(id: DeterministicID.uuid(from: "c"), text: "Не ест после семи", kind: .constraint, source: .manual, createdAt: old, isPinned: true),
        ])
        let result = consolidator.merge([], into: memory, source: .chat, time: time)
        #expect(result.memory.facts.map(\.text) == ["Часто работает ночью", "Не ест после семи"])
    }

    @Test("Лимит памяти: вытесняется самое слабое, закреплённое остаётся")
    func cap() {
        let small = MemoryConsolidator(maxFacts: 3)
        var memory = UserMemory(facts: [
            MemoryFact(id: DeterministicID.uuid(from: "pin"), text: "Закреплённый факт номер один", kind: .context, source: .manual,
                       createdAt: WowFixture.moment(9, 0, dayOffset: -20), isPinned: true),
        ])
        for (index, text) in ["Любит длинные прогулки вечером", "Готовится к марафону весной", "Пьёт много кофе по утрам"].enumerated() {
            let moment = WowFixture.time(9, 0, dayOffset: -10 + index)
            memory = small.merge([MemoryCandidate(text: text)], into: memory, source: .chat, time: moment).memory
        }
        #expect(memory.facts.count == 3)
        #expect(memory.facts.contains { $0.isPinned })
        #expect(!memory.facts.contains { $0.text == "Любит длинные прогулки вечером" })
    }
}

@Suite("Ядро контекста: бюджет токенов")
struct UserContextBuilderTests {
    private let builder = UserContextBuilder()
    private let time = WowFixture.evening

    private func entry(dayOffset: Int, digest: String, transcript: String? = nil) -> CheckInEntry {
        let day = WowFixture.calendar.startOfDay(for: WowFixture.moment(12, 0, dayOffset: dayOffset))
        return CheckInEntry(
            id: DeterministicID.uuid(from: "entry\(dayOffset)"), day: day, createdAt: day, updatedAt: day,
            source: .text, transcript: transcript,
            report: CheckInReport(completed: [ReportedTask(taskID: nil, title: "Работа", minutes: 60, status: .done)],
                                  rating: .ok, plannedCount: 2, completedPlannedCount: 1),
            digest: digest, extractorID: "rules"
        )
    }

    private var memory: UserMemory {
        UserMemory(facts: [
            MemoryFact(id: DeterministicID.uuid(from: "f1"), text: "После обеда проседает концентрация", kind: .pattern,
                       source: .chat, createdAt: WowFixture.moment(9, 0, dayOffset: -30), confirmations: 4),
            MemoryFact(id: DeterministicID.uuid(from: "f2"), text: "По вторникам зал в 19:00", kind: .pattern,
                       source: .manual, createdAt: WowFixture.moment(9, 0, dayOffset: -40), isPinned: true),
            MemoryFact(id: DeterministicID.uuid(from: "f3"), text: "Готовится к марафону в октябре", kind: .context,
                       source: .chat, createdAt: WowFixture.moment(9, 0, dayOffset: -2)),
        ])
    }

    @Test("Год дневника не раздувает запрос: блок остаётся в бюджете")
    func boundedByBudget() {
        let journal = (1...365).map { offset in
            entry(dayOffset: -offset,
                  digest: "День \(offset): сделано 3 из 5, работа ≈ 6 ч, день: нормально. Сделано: «Отчёт», «Созвон», «Код».",
                  transcript: String(repeating: "Сегодня работал над отчётом, потом созвон и код. ", count: 40))
        }
        let context = builder.build(memory: memory, journal: journal, query: "как прошла прошлая неделя?", time: time)
        #expect(context.estimatedTokens <= UserContextBudget.standard.maxTokens)
        #expect(context.dayCount <= UserContextBudget.standard.recentDays + UserContextBudget.standard.retrievedDays)
        // Сырого рассказа в контексте нет — только выжимки.
        #expect(!context.text.contains("Сегодня работал над отчётом, потом созвон и код. Сегодня"))
    }

    @Test("Сначала закреплённое, потом относящееся к вопросу")
    func factOrdering() {
        let context = builder.build(memory: memory, journal: [], query: "что с марафоном?", time: time)
        let lines = context.text.split(separator: "\n").map(String.init)
        #expect(lines.first == "Что известно о человеке:")
        #expect(lines[1] == "- По вторникам зал в 19:00")
        #expect(lines[2] == "- Готовится к марафону в октябре")
        #expect(context.factCount == 3)
    }

    @Test("Старый день находится по вопросу, с цитатой, если в выжимке его нет")
    func retrieval() {
        let journal = [
            entry(dayOffset: -1, digest: "08.09, вт: сделано 2 из 3."),
            entry(dayOffset: -20, digest: "20.08, чт: сделано 1 из 4.", transcript: "Днём ходил к стоматологу. Вечером отчёт."),
            entry(dayOffset: -25, digest: "15.08, сб: сделано 4 из 4."),
        ]
        let context = builder.build(memory: .empty, journal: journal, query: "когда я был у стоматолога?", time: time)
        #expect(context.text.contains("Последние дни:\n- 08.09, вт: сделано 2 из 3."))
        #expect(context.text.contains("Похожие дни раньше:\n- 20.08, чт: сделано 1 из 4. Из рассказа: «Днём ходил к стоматологу»"))
        #expect(!context.text.contains("15.08"))
    }

    @Test("Пустая память — пустой блок")
    func empty() {
        #expect(builder.build(memory: .empty, journal: [], query: nil, time: time).isEmpty)
    }

    @Test("Оценка токенов: кириллица дороже латиницы")
    func tokenEstimate() {
        #expect(TokenEstimator.estimate("") == 0)
        #expect(TokenEstimator.estimate("привет") == 3)
        #expect(TokenEstimator.estimate("hello world!") == 3)
    }
}
