import Testing
import Foundation
@testable import LineaCore

@Suite("Итог дня: запрос к модели и чтение ответа")
struct CheckInPromptTests {
    private let request = CheckInFixture.request(facts: ["По вторникам зал в 19:00"])
    private var prompt: CheckInPrompt { CheckInPrompt(tasks: request.tasks) }

    @Test("Задачи идут под номерами, без идентификаторов")
    func numberedTasks() {
        let text = prompt.user(for: request)
        #expect(text.contains("1. Презентация КП"))
        #expect(text.contains("5. Тренировка"))
        #expect(!text.contains(WowFixture.taskA.uuidString))
        #expect(text.contains("Уже известно:\n- По вторникам зал в 19:00"))
        #expect(text.hasSuffix("не закончил. Ещё созвонился с поставщиком минут на сорок. Работал часов семь. День тяжёлый, очень устал. Запомни, что после обеда я плохо соображаю.»"))
    }

    @Test("Запрос экономный: разбор пятиминутного рассказа — несколько тысяч токенов, а не десятки")
    func tokenCost() {
        // Пять минут речи — примерно 700 слов.
        let story = Array(repeating: "Сегодня сделал презентацию и ответил на письма, потом был созвон.", count: 70).joined(separator: " ")
        let cost = TokenEstimator.estimate(CheckInPrompt.systemPrompt) + TokenEstimator.estimate(prompt.user(for: CheckInFixture.request(story)))
        #expect(cost < 4_000)
        #expect(cost > 1_000)
    }

    @Test("Ответ в ```-блоке, номера строками, оценка по-русски")
    func tolerantDecoding() throws {
        let answer = """
        Вот разбор:
        ```json
        {"done":["1", 3, 4.0],"partial":[2],"not_done":[5],"mentioned":[],
         "extra":[{"title":"созвон с поставщиком","minutes":"40"}],
         "work_minutes":420,"rating":"тяжело","energy":"low",
         "summary":"Тяжёлый день: главное сделано, тренировка сорвалась.",
         "remember":[{"text":"После обеда концентрация падает","kind":"pattern"}, "Любит работать утром"]}
        ```
        """
        let extraction = try prompt.decode(answer, extractorID: "cloud")
        #expect(extraction.outcome(for: WowFixture.taskA)?.status == .done)
        #expect(extraction.outcome(for: WowFixture.taskB)?.status == .partial)
        #expect(extraction.outcome(for: WowFixture.taskC)?.status == .done)
        #expect(extraction.outcome(for: WowFixture.taskCall)?.status == .done)
        #expect(extraction.outcome(for: WowFixture.taskWorkout)?.status == .notDone)
        #expect(extraction.extra == [ExtraWork(title: "созвон с поставщиком", minutes: 40)])
        #expect(extraction.statedWorkMinutes == 420)
        #expect(extraction.rating == .hard)
        #expect(extraction.energy == .low)
        #expect(extraction.summary == "Тяжёлый день: главное сделано, тренировка сорвалась.")
        #expect(extraction.memory.map(\.kind) == [.pattern, .preference])
        #expect(extraction.extractorID == "cloud")
    }

    @Test("Противоречие решается в пользу осторожного, чужие номера отбрасываются")
    func conflicts() throws {
        let extraction = try prompt.decode(#"{"done":[1,5,42],"not_done":[5],"mentioned":[2]}"#, extractorID: "cloud")
        #expect(extraction.outcome(for: WowFixture.taskWorkout)?.status == .notDone)
        #expect(extraction.outcome(for: WowFixture.taskB) == TaskOutcome(taskID: WowFixture.taskB, status: .done, isConfident: false))
        #expect(extraction.outcomes.count == 3)
    }

    @Test("Огромные числа в ответе модели отбрасываются, а не роняют приложение")
    func hugeNumbers() throws {
        let answer = #"{"done":[1e30, 2],"work_minutes":1e300,"extra":[{"title":"созвон","minutes":9.3e18}]}"#
        let extraction = try prompt.decode(answer, extractorID: "cloud")
        #expect(extraction.outcomes.map(\.taskID) == [WowFixture.taskB])
        #expect(extraction.statedWorkMinutes == nil)
        #expect(extraction.extra == [ExtraWork(title: "созвон", minutes: nil)])
    }

    @Test("Не JSON — ошибка, а не пустой разбор")
    func malformed() {
        #expect(throws: CheckInPrompt.DecodingError.noJSON) { try prompt.decode("Извини, не понял.", extractorID: "cloud") }
        #expect(throws: CheckInPrompt.DecodingError.malformed) { try prompt.decode("{done: [1}", extractorID: "cloud") }
    }
}

@Suite("Итог дня: проверка ответа модели")
struct CheckInValidatorTests {
    private let validator = CheckInExtractionValidator()
    private let request = CheckInFixture.request()

    @Test("Лишнее отбрасывается поштучно, полезное остаётся")
    func sanitize() {
        let raw = CheckInExtraction(
            outcomes: [
                TaskOutcome(taskID: WowFixture.taskA, status: .done),
                TaskOutcome(taskID: UUID(uuidString: "00000000-0000-0000-0000-00000000DEAD")!, status: .done),
                TaskOutcome(taskID: WowFixture.taskA, status: .notDone),
            ],
            extra: [
                ExtraWork(title: "созвон с поставщиком", minutes: 40),
                ExtraWork(title: "Презентация КП", minutes: 30),          // это задача из списка
                ExtraWork(title: "Созвон с поставщиком", minutes: 9_999), // повтор
                ExtraWork(title: "x", minutes: nil),
            ],
            statedWorkMinutes: 2_000,
            summary: "Работал 12 часов и выпил таблетку.",
            memory: [
                MemoryCandidate(text: "После обеда концентрация падает", kind: .pattern),
                MemoryCandidate(text: "Принимает лекарство от давления", kind: .context),
                MemoryCandidate(text: "Встаёт в 6:00 по будням", kind: .pattern),
                MemoryCandidate(text: "After lunch he is slow", kind: .pattern),
            ],
            extractorID: "cloud"
        )
        let clean = validator.sanitize(raw, request: request)
        #expect(clean.outcomes == [TaskOutcome(taskID: WowFixture.taskA, status: .done)])
        #expect(clean.extra == [ExtraWork(title: "Созвон с поставщиком", minutes: 40)])
        #expect(clean.statedWorkMinutes == nil)
        #expect(clean.summary == nil)
        // Здоровье без просьбы не запоминается; «6:00» в рассказе не звучало; английский — мимо.
        #expect(clean.memory.map(\.text) == ["После обеда концентрация падает"])
    }

    @Test("Явную просьбу про здоровье запоминаем: человек сам попросил")
    func explicitHealthFact() {
        let raw = CheckInExtraction(memory: [MemoryCandidate(text: "По утрам меряю давление", kind: .pattern, isExplicit: true)], extractorID: "rules")
        let clean = validator.sanitize(raw, request: CheckInFixture.request("Запомни, что по утрам меряю давление."))
        #expect(clean.memory.count == 1)
    }

    @Test("Модель не ответила — разбор правилами, итог дня не ломается")
    func fallbackOnError() async throws {
        let extractor = FallbackCheckInExtractor(primary: FailingExtractor())
        let extraction = try await extractor.extract(request)
        #expect(extraction.extractorID == "rules")
        #expect(extraction.outcome(for: WowFixture.taskA)?.status == .done)
    }

    @Test("Модель главная, но явное «запомни» и пропущенные задачи не теряются")
    func mergeKeepsExplicitMemory() async throws {
        let modelAnswer = CheckInExtraction(
            outcomes: [TaskOutcome(taskID: WowFixture.taskA, status: .done)],
            memory: [MemoryCandidate(text: "Любит работать утром", kind: .preference)],
            extractorID: "cloud"
        )
        let extractor = FallbackCheckInExtractor(primary: FixedExtractor(extraction: modelAnswer))
        let extraction = try await extractor.extract(request)
        #expect(extraction.extractorID == "cloud")
        #expect(extraction.memory.first?.text == "После обеда я плохо соображаю")
        #expect(extraction.memory.first?.isExplicit == true)
        #expect(extraction.memory.contains { $0.text == "Любит работать утром" })
        // Задачу C модель пропустила, правила нашли — без галочки, решает человек.
        #expect(extraction.outcome(for: WowFixture.taskC) == TaskOutcome(taskID: WowFixture.taskC, status: .done, isConfident: false))
        // Оценку модель не дала — берём из правил.
        #expect(extraction.rating == .hard)
    }
}

private struct FailingExtractor: CheckInExtracting {
    let id = "cloud"
    func extract(_ request: CheckInRequest) async throws -> CheckInExtraction {
        throw CheckInPrompt.DecodingError.noJSON
    }
}

private struct FixedExtractor: CheckInExtracting {
    let id = "cloud"
    let extraction: CheckInExtraction
    func extract(_ request: CheckInRequest) async throws -> CheckInExtraction { extraction }
}
