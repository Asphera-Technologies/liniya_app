import Testing
import Foundation
@testable import LineaCore

/// Новая цель: из сырой формулировки и рассказа — «Я поняла цель так».
/// Время — среда 9 сентября 2026, 08:00 по Москве.
@Suite("Новая цель: разбор")
struct GoalAnalyzerTests {
    private let time = WowFixture.morning
    private let analyzer = RuleBasedGoalAnalyzer()

    private func understand(_ input: GoalIntakeInput) -> GoalUnderstanding {
        analyzer.understand(input, profile: WowFixture.profile, time: time)
    }

    @Test("Пример заказчика: сейчас, результат и признаки — без вопросов")
    func customerExample() {
        let result = understand(GoalIntakeInput(
            title: "Запустить закрытую beta Linea",
            details: "У нас уже есть рабочий прототип приложения. Сейчас идёт переработка задач и онбординга. "
                + "Хотим, чтобы приложение было доступно через TestFlight и подключить 50 тестировщиков."
        ))
        #expect(result.title == "Запустить закрытую beta Linea")
        #expect(result.currentState == "Уже есть рабочий прототип приложения. Идёт переработка задач и онбординга.")
        #expect(result.targetState == "Приложение доступно через TestFlight и подключить 50 тестировщиков.")
        #expect(result.successCriteria == ["Приложение доступно через TestFlight", "Подключить 50 тестировщиков"])
        #expect(result.deadline == nil)
        #expect(result.question == nil)
        #expect(result.details?.hasPrefix("У нас уже есть рабочий прототип") == true)
    }

    @Test("Одно название «Запустить продукт» — Linea спрашивает, как поймём, что цель достигнута")
    func titleOnlyAsksForResult() {
        let result = understand(GoalIntakeInput(title: "запустить продукт"))
        #expect(result.title == "Запустить продукт")
        #expect(result.question == .result)
        #expect(result.question?.text == "Как поймём, что цель достигнута?")
        #expect(result.successCriteria.isEmpty)
        #expect(result.targetState == nil)
        #expect(result.currentState == nil)
    }

    @Test("Вопросы по одному: ответ на первый — и только тогда второй; пропущенный не повторяется")
    func oneQuestionAtATime() {
        var input = GoalIntakeInput(title: "Запустить продукт")
        input.answers[.result] = "Первые 100 платящих пользователей"
        let second = understand(input)
        #expect(second.successCriteria == ["Первые 100 платящих пользователей"])
        #expect(second.targetState == "Первые 100 платящих пользователей.")
        #expect(second.question == .start)
        #expect(second.question?.text == "С чего начинаем — что уже есть?")

        input.answers[.start] = "Есть лендинг и список ожидания на 300 человек"
        let done = understand(input)
        #expect(done.question == nil)
        #expect(done.currentState == "Есть лендинг и список ожидания на 300 человек.")
        #expect(done.details == "Как поймём, что цель достигнута? Первые 100 платящих пользователей\n"
            + "С чего начинаем — что уже есть? Есть лендинг и список ожидания на 300 человек")

        var skipped = GoalIntakeInput(title: "Запустить продукт", skipped: [.result])
        #expect(understand(skipped).question == .start)
        skipped.skipped.insert(.start)
        let quiet = understand(skipped)
        #expect(quiet.question == nil)
        #expect(quiet.title == "Запустить продукт")
    }

    @Test("Ответ без чисел — тоже ответ: вопрос о результате не повторяется")
    func vagueAnswerIsAccepted() {
        var input = GoalIntakeInput(title: "Сделать сайт студии")
        input.answers[.result] = "Чтобы клиентам было понятно, чем мы занимаемся"
        let result = understand(input)
        #expect(result.question == .start)
        #expect(result.successCriteria == ["Клиентам понятно, чем мы занимаемся"])
    }

    @Test("Число в названии — уже признак успеха; рассказ без желаемого — это «Сейчас»")
    func measurableTitle() {
        let result = understand(GoalIntakeInput(title: "Пробежать 10 км", details: "Сейчас бегаю по 3 км, пока тяжело."))
        #expect(result.successCriteria == ["Пробежать 10 км"])
        #expect(result.targetState == "Пробежать 10 км.")
        #expect(result.currentState == "Бегаю по 3 км. Пока тяжело.")
        #expect(result.question == nil)
    }

    @Test("Срок из рассказа о результате: «к 1 декабря»")
    func deadlineFromResult() throws {
        let result = understand(GoalIntakeInput(
            title: "Выпустить приложение",
            details: "Код почти готов. Хочу к 1 декабря выйти в App Store."
        ))
        #expect(result.successCriteria == ["К 1 декабря выйти в App Store"])
        #expect(result.currentState == "Код почти готов.")
        let deadline = try #require(result.deadline)
        #expect(WowFixture.calendar.component(.month, from: deadline) == 12)
        #expect(WowFixture.calendar.component(.day, from: deadline) == 1)
    }

    @Test("Части предложения: «сейчас … , а нужно …» делятся на «Сейчас» и «Результат»")
    func contrastClauses() {
        let result = understand(GoalIntakeInput(
            title: "Похудеть",
            details: "Сейчас вешу 82 кг, а нужно 75 кг к лету"
        ))
        #expect(result.currentState == "Вешу 82 кг.")
        #expect(result.targetState == "75 кг к лету.")
        #expect(result.successCriteria == ["75 кг к лету"])
    }

    @Test("Короткие слова не путаются: «показать» — не «пока», «статью» — не «стать»")
    func wholeWordMarkers() {
        #expect(RuleBasedGoalAnalyzer.side(of: "Показать демо инвесторам") == nil)
        #expect(RuleBasedGoalAnalyzer.side(of: "Пишу статью про Linea") == nil)
        #expect(RuleBasedGoalAnalyzer.side(of: "Пока нет ни одного пользователя") == .current)
        #expect(RuleBasedGoalAnalyzer.side(of: "Хочу выйти на 2,5 тысячи подписчиков") == .target)
        #expect(RuleBasedGoalAnalyzer.sentences("Вешу 82.5 кг. Хочу 75") == ["Вешу 82.5 кг", "Хочу 75"])
        #expect(RuleBasedGoalAnalyzer.clauses("Сейчас 2,5 тысячи, а хотим 10") == ["Сейчас 2,5 тысячи", "а хотим 10"])
    }

    @Test("«Всё верно» создаёт цель с тем, что увидел человек; без чисел — ничего придуманного")
    func goalFromUnderstanding() {
        let understanding = GoalUnderstanding(
            title: "  Запустить закрытую beta Linea ",
            currentState: "Уже есть прототип.",
            targetState: "Приложение доступно через TestFlight.",
            successCriteria: ["Приложение доступно через TestFlight", " "],
            deadline: WowFixture.moment(18, 0, dayOffset: 30),
            details: "Рассказ"
        )
        let goal = understanding.goal(id: WowFixture.goalMVP, createdAt: time.now, time: time)
        #expect(goal.title == "Запустить закрытую beta Linea")
        #expect(goal.currentState == "Уже есть прототип.")
        #expect(goal.targetState == "Приложение доступно через TestFlight.")
        #expect(goal.successCriteria == ["Приложение доступно через TestFlight"])
        #expect(goal.endDate == time.startOfDay(WowFixture.moment(18, 0, dayOffset: 30)))
        #expect(goal.details == "Рассказ")
        #expect(goal.isActive)
        #expect(goal.progress == 0)
    }

    @Test("Цель из старого документа дня читается без новых полей")
    func legacyGoalDecodes() throws {
        let json = #"{"id":"\#(WowFixture.goalMVP.uuidString)","title":"Старая цель","createdAt":0}"#
        let goal = try JSONDecoder().decode(LineaGoal.self, from: Data(json.utf8))
        #expect(goal.title == "Старая цель")
        #expect(goal.successCriteria.isEmpty)
        #expect(goal.currentState == nil)
    }
}
