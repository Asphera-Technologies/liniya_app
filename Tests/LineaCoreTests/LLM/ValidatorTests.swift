import Testing
import Foundation
@testable import LineaCore

@Suite("Проверка текста от модели")
struct ExplanationValidatorTests {
    private let validator = ExplanationValidator()
    private let time = WowFixture.morning

    private var facts: [Fact] {
        [
            .loadAdvice(.reduce),
            .topTaskCount(3),
            .hardWorkDeadline(WowFixture.moment(12)),
            .sleepDuration(seconds: 21_780),
            .sleepVsUsual(deltaSeconds: -4_200, level: .belowUsual),
            .recovery(level: .belowUsual),
        ]
    }

    private func explanation(_ body: String, headline: String = "Доброе утро.") -> Explanation {
        Explanation(headline: headline, body: body, explainerID: "test")
    }

    @Test("Текст из фактов проходит")
    func valid() {
        let result = validator.validate(
            explanation("У тебя есть 3 приоритетных действия. Сложное лучше закрыть до 12:00."),
            facts: facts, taskTitles: [], time: time
        )
        #expect(result == .valid)
    }

    @Test("Придуманное число отклоняется")
    func inventedNumber() {
        let result = validator.validate(
            explanation("У тебя есть 7 приоритетных действий."),
            facts: facts, taskTitles: [], time: time
        )
        #expect(result != .valid)
    }

    @Test("«Обычно» без личной нормы отклоняется")
    func usualWithoutBaseline() {
        let bare: [Fact] = [.loadAdvice(.reduce), .topTaskCount(3)]
        #expect(validator.validate(explanation("Ты спал меньше обычного."), facts: bare, taskTitles: [], time: time) != .valid)
        #expect(validator.validate(explanation("Ты спал меньше обычного."), facts: facts, taskTitles: [], time: time) == .valid)
    }

    @Test("Слишком много латиницы отклоняется")
    func latin() {
        let result = validator.validate(
            explanation("Today is a reduced load day, take it easy please."),
            facts: facts, taskTitles: [], time: time
        )
        #expect(result != .valid)
    }

    @Test("Медицинские формулировки отклоняются")
    func medical() {
        let result = validator.validate(
            explanation("Похоже на болезнь, прими лекарство."),
            facts: facts, taskTitles: [], time: time
        )
        #expect(result != .valid)
    }

    @Test("Чужое название задачи отклоняется")
    func unknownTask() {
        #expect(validator.validate(explanation("Закрываем «Отчёт для банка» сейчас?"), facts: facts, taskTitles: ["Презентация КП"], time: time) != .valid)
        #expect(validator.validate(explanation("Закрываем «Презентация КП» сейчас?"), facts: facts, taskTitles: ["Презентация КП"], time: time) == .valid)
    }

    @Test("Слишком длинный ответ отклоняется")
    func tooLong() {
        let body = "Сегодня стоит поберечь силы. Начни со сложного. Потом отдохни. И ещё одно предложение."
        #expect(validator.validate(explanation(body), facts: facts, taskTitles: [], time: time) != .valid)
    }

    @Test("Разрешённые числа собираются из фактов")
    func allowedNumbers() {
        let allowed = validator.allowedNumbers(facts: facts, time: time)
        #expect(allowed.contains("6:03"))     // длительность сна
        #expect(allowed.contains("12:00"))    // окно глубокой работы
        #expect(allowed.contains("3"))        // число приоритетов
        #expect(allowed.contains("1"))        // «1 ч 10 мин» отставания от нормы
        #expect(allowed.contains("10"))
        #expect(!allowed.contains("7"))
    }

    @Test("Разбор чисел и кавычек")
    func parsing() {
        #expect(ExplanationValidator.numericTokens(in: "Сон 6:03 — на 1 ч 10 мин меньше") == ["6:03", "1", "10"])
        #expect(ExplanationValidator.quotedFragments(in: "Закрываем «Презентация КП» сейчас?") == ["Презентация КП"])
        #expect(ExplanationValidator.sentenceCount("Раз. Два! Три?") == 3)
        #expect(ExplanationValidator.cyrillicShare("Привет") == 1)
    }
}

@Suite("Запасной объяснитель")
struct FallbackExplainerTests {
    private let request = ExplanationRequest(
        moment: .morning,
        facts: [.loadAdvice(.reduce), .topTaskCount(3)],
        hour: 8,
        timeZoneIdentifier: WowFixture.timeZoneID
    )

    @Test("Без модели работают шаблоны")
    func noPrimary() async throws {
        let explanation = try await FallbackExplainer(primary: nil).explain(request)
        #expect(explanation.headline == "Доброе утро. Сегодня нагрузку лучше немного снизить.")
        #expect(explanation.explainerID == "rule-based")
    }

    @Test("Валидный ответ модели заменяет только тело")
    func primaryWins() async throws {
        let primary = ScriptedExplainer(id: "on-device", body: "У тебя есть 3 приоритетных действия.")
        let explanation = try await FallbackExplainer(primary: primary).explain(request)
        #expect(explanation.headline == "Доброе утро. Сегодня нагрузку лучше немного снизить.")
        #expect(explanation.body == "У тебя есть 3 приоритетных действия.")
        #expect(explanation.explainerID == "on-device")
    }

    @Test("Ошибка модели возвращает шаблон")
    func primaryFails() async throws {
        let primary = ScriptedExplainer(id: "on-device", body: "", error: FakeError(message: "нет модели"))
        let explanation = try await FallbackExplainer(primary: primary).explain(request)
        #expect(explanation.explainerID == "rule-based")
    }

    @Test("Медленная модель не задерживает утро")
    func primaryTimesOut() async throws {
        let primary = ScriptedExplainer(id: "on-device", body: "Слишком поздно.", delay: .milliseconds(400))
        let explanation = try await FallbackExplainer(primary: primary, timeout: .milliseconds(50)).explain(request)
        #expect(explanation.explainerID == "rule-based")
    }

    @Test("Выдуманное число отбрасывает ответ модели")
    func primaryHallucinates() async throws {
        let primary = ScriptedExplainer(id: "on-device", body: "У тебя есть 9 приоритетных действий.")
        let explanation = try await FallbackExplainer(primary: primary).explain(request)
        #expect(explanation.explainerID == "rule-based")
        #expect(explanation.body == "У тебя есть 3 приоритетных действия.")
    }
}
