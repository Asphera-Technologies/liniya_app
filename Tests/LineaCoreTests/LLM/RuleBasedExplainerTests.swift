import Testing
import Foundation
@testable import LineaCore

/// Golden-строки: это ровно те фразы, которые обещает продукт (Docs/brief.md).
/// Если тест здесь падает — изменился текст, который увидит пользователь.
@Suite("Тексты Linea")
struct RuleBasedExplainerTests {
    private let explainer = RuleBasedExplainer()
    private let tz = WowFixture.timeZoneID

    private func request(_ moment: ExplanationMoment, _ facts: [Fact], hour: Int = 8, taskTitles: [String] = []) -> ExplanationRequest {
        ExplanationRequest(moment: moment, facts: facts, taskTitles: taskTitles, hour: hour, timeZoneIdentifier: tz)
    }

    private var morningFacts: [Fact] {
        [
            .loadAdvice(.reduce),
            .topTaskCount(3),
            .hardWorkDeadline(WowFixture.moment(12)),
            .sleepDuration(seconds: 21_780),
            .sleepBaseline(seconds: 25_980),
            .sleepVsUsual(deltaSeconds: -4_200, level: .belowUsual),
            .recovery(level: .belowUsual),
        ]
    }

    // MARK: Утро

    @Test("Утро wow-сценария слово в слово")
    func morning() {
        let text = explainer.render(request(.morning, morningFacts))
        #expect(text.headline == "Доброе утро. Сегодня нагрузку лучше немного снизить.")
        #expect(text.body == "У тебя есть 3 приоритетных действия. Самую сложную работу предлагаю сделать до 12:00.")
        #expect(text.reasons == [
            "Сон 6:03 — на 1 ч 10 мин меньше обычного.",
            "Восстановление ниже обычного.",
        ])
        #expect(text.explainerID == "rule-based")
    }

    @Test("Без окна глубокой работы второе предложение исчезает")
    func morningWithoutDeadline() {
        let facts = morningFacts.filter { if case .hardWorkDeadline = $0 { return false }; return true }
        #expect(explainer.render(request(.morning, facts)).body == "У тебя есть 3 приоритетных действия.")
    }

    @Test("Склонение и пустой день")
    func morningCounts() {
        func body(_ count: Int) -> String {
            explainer.render(request(.morning, [.loadAdvice(.normal), .topTaskCount(count)])).body
        }
        #expect(body(1) == "У тебя есть 1 приоритетное действие.")
        #expect(body(5) == "У тебя есть 5 приоритетных действий.")
        #expect(body(0) == "На сегодня задач нет.")
    }

    @Test("Вердикт по нагрузке звучит только когда он есть")
    func morningAdvice() {
        #expect(explainer.render(request(.morning, [.loadAdvice(.normal)])).headline == "Доброе утро.")
        #expect(explainer.render(request(.morning, [.loadAdvice(.push)])).headline == "Доброе утро. Сегодня можно взять больше.")
        #expect(explainer.render(request(.morning, [.loadAdvice(.unknown)])).headline == "Доброе утро.")
        #expect(explainer.render(request(.morning, [.loadAdvice(.reduce)], hour: 14)).headline == "Добрый день. Сегодня нагрузку лучше немного снизить.")
    }

    @Test("Пока нет базы — никакого «обычного»")
    func morningColdStart() {
        let facts: [Fact] = [.loadAdvice(.unknown), .topTaskCount(2), .sleepDuration(seconds: 21_780), .coldStart(days: 3, needed: 7)]
        let text = explainer.render(request(.morning, facts))
        #expect(text.reasons == [
            "Сон 6:03.",
            "Собираю базу: день 3 из 7 — сравнивать с обычным пока рано.",
        ])
        #expect(!text.headline.contains("обычн"))
    }

    @Test("Нет данных о сне — так и сказано")
    func morningNoSleep() {
        let facts: [Fact] = [.loadAdvice(.unknown), .topTaskCount(2), .dataMissing(kind: .sleepSegment)]
        #expect(explainer.render(request(.morning, facts)).reasons == ["Не вижу данных о сне — планирую по времени и приоритетам."])
    }

    // MARK: Нудж

    @Test("Нудж 14:30 слово в слово")
    func nudge() {
        let facts: [Fact] = [
            .behindSchedule(taskID: WowFixture.taskA, title: "Презентация КП", lagMinutes: 240),
            .nextCommitment(title: "Созвон с командой", at: WowFixture.moment(15, 50), minutesLeft: 80),
        ]
        let text = explainer.render(request(.nudge, facts, hour: 14))
        #expect(text.headline == "План немного отстаёт.")
        #expect(text.body == "До следующего обязательства осталось 1 ч 20 мин. Закрываем «Презентация КП» сейчас или переносим?")
    }

    @Test("Без обязательств впереди считается конец рабочего дня")
    func nudgeEndOfDay() {
        let facts: [Fact] = [
            .behindSchedule(taskID: WowFixture.taskA, title: "Презентация КП", lagMinutes: 60),
            .endOfWorkday(minutesLeft: 95),
        ]
        #expect(explainer.render(request(.nudge, facts, hour: 19)).body
            == "До конца рабочего дня осталось 1 ч 35 мин. Закрываем «Презентация КП» сейчас или переносим?")
    }

    // MARK: Остальные моменты

    @Test("Вечерний вопрос — три слова")
    func evening() {
        let text = explainer.render(request(.evening, [], hour: 21))
        #expect(text.headline == "Как прошёл день?")
        #expect(text.body.isEmpty)
    }

    @Test("Совет по нагрузке отдельной карточкой")
    func loadAdjustment() {
        let text = explainer.render(request(.loadAdjustment, morningFacts))
        #expect(text.headline == "Сегодня нагрузку лучше немного снизить.")
        #expect(text.reasons.first == "Сон 6:03 — на 1 ч 10 мин меньше обычного.")
    }

    @Test("Обед: легче при сниженной нагрузке, с продуктами из профиля")
    func meal() {
        let facts: [Fact] = [
            .mealWindow(kind: .lunch, start: WowFixture.moment(13), end: WowFixture.moment(13, 40)),
            .loadAdvice(.reduce),
            .dietRestrictions(count: 1),
        ]
        let text = explainer.render(request(.meal, facts, hour: 11, taskTitles: ["овсянка", "курица", "овощи", "рыба"]))
        #expect(text.headline == "Обед в 13:00 лучше сделать полегче.")
        #expect(text.body == "Например: овсянка, курица, овощи.")

        let plain = explainer.render(request(.meal, [.mealWindow(kind: .lunch, start: WowFixture.moment(13), end: WowFixture.moment(13, 40))], hour: 11))
        #expect(plain.headline == "Обед в 13:00.")
        #expect(plain.body.isEmpty)
    }

    @Test("Перекус перед тренировкой")
    func preWorkoutMeal() {
        let text = explainer.render(request(.meal, [.workoutPlanned(at: WowFixture.moment(17))], hour: 15))
        #expect(text.headline == "Перед тренировкой в 17:00 стоит перекусить.")
    }

    @Test("Перенос задачи называет причину")
    func deferred() {
        let facts: [Fact] = [.taskDeferred(taskID: WowFixture.taskB, title: "Разработка Linea", reason: "Нагрузка снижена из-за сна.")]
        let text = explainer.render(request(.taskDeferred, facts, hour: 10))
        #expect(text.headline == "«Разработка Linea» переносим.")
        #expect(text.body == "Нагрузка снижена из-за сна.")
    }
}
