import Testing
import Foundation
@testable import LineaCore

/// Быстрая цель: одна строка — название, срок, тип; под ней — чипы.
/// Время — среда 9 сентября 2026, 08:00 по Москве.
@Suite("Быстрая цель")
struct QuickGoalTests {
    private let time = WowFixture.morning
    private let profile = WowFixture.profile

    private func line(_ text: String) -> GoalLineParse {
        GoalLineParser.parse(text, profile: profile, time: time)
    }

    private func day(_ month: Int, _ day: Int, _ year: Int = 2026) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return WowFixture.calendar.date(from: components)!
    }

    private func resolve(_ draft: QuickGoalDraft) -> QuickGoalResolution {
        draft.resolve(profile: profile, time: time)
    }

    // MARK: Пример заказчика

    @Test("«Выпустить Линия в TestFlight до 15-го октября» → название, срок 15 октября, проект, этапы")
    func customerExample() {
        let resolution = resolve(QuickGoalDraft(text: "Выпустить Линия в TestFlight до 15-го октября"))
        let understanding = resolution.understanding
        #expect(resolution.title == "Выпустить Линия в TestFlight", "Слова человека не переписываются")
        #expect(understanding.deadline == day(10, 15))
        #expect(understanding.kind == .project)
        #expect(understanding.method == .milestones)
        #expect(understanding.scope == .personal)
        #expect(understanding.ownerScope == nil)
        #expect(understanding.stages == ["Исследование", "Разработка", "Подготовка запуска", "Тестирование", "Запуск", "Рост"])
        #expect(understanding.stage == nil, "О том, где цель сейчас, не сказано — стадия не выбрана")
        #expect(understanding.milestones.isEmpty, "Название этапом не бывает")
        #expect(understanding.successCriteria.isEmpty, "Одна строка — название, а не признак успеха")
        #expect(understanding.targetState == nil)
        #expect(resolution.isUnderstood)
        #expect(resolution.deadlineOrigin == .typed)
        #expect(resolution.priorityOrigin == .assumed)
        #expect(QuickGoalText.summary(resolution, time: time) == "до 15 октября")
        #expect(QuickGoalText.deadlineChip(resolution, time: time) == "до 15 окт")
        #expect(QuickGoalText.methodChip(resolution) == "Этапы")
        #expect(understanding.question == .start, "Подробнее — по желанию; быстрая цель вопрос не задаёт")

        let goal = resolution.goal(id: WowFixture.goalMVP, createdAt: time.now, time: time)
        #expect(goal.title == "Выпустить Линия в TestFlight")
        #expect(goal.endDate == day(10, 15))
        #expect(goal.priority == .normal)
        #expect(goal.progressMethod == .milestones)
        #expect(goal.stages.count == 6)
        #expect(goal.scope == .personal)
        #expect(goal.kindOverride == nil)
        #expect(goal.lastReviewedAt == time.now)
        #expect(goal.isActive)
    }

    @Test("«15-го октября» понимает и быстрая задача")
    func ordinalDateInTask() throws {
        let parsed = QuickTaskParser().parse("Сдать отчёт до 15-го октября", time: time)
        #expect(parsed.title == "Сдать отчёт")
        let deadline = try #require(parsed.deadline)
        #expect(time.startOfDay(deadline) == day(10, 15))
        let tokens = CaptureTokenizer.tokens("до 15-го и 20-30 минут")
        #expect(tokens.map(\.word) == ["до", "15", "и", "20", "", "30", "минут"], "Диапазон «20-30» — не окончание")
    }

    // MARK: Сроки цели

    @Test("Сроки масштаба цели: конец года, месяц, сезон, «за 3 месяца», «через полгода», год")
    func horizons() {
        #expect(line("Накопить подушку до конца года").deadline == day(12, 31))
        #expect(line("Накопить подушку до конца года").title == "Накопить подушку")
        #expect(line("Сдать проект к концу следующего месяца").deadline == day(10, 31))
        #expect(line("Закрыть квартал до конца квартала").deadline == day(9, 30))
        #expect(line("Выпустить книгу в декабре").deadline == day(12, 31))
        #expect(line("Выпустить книгу в декабре").title == "Выпустить книгу")
        #expect(line("Переехать к декабрю").deadline == day(12, 1))
        #expect(line("Переехать до декабря").deadline == day(12, 1))
        #expect(line("Похудеть на 5 кг к лету").deadline == day(6, 1, 2027))
        #expect(line("Похудеть на 5 кг к лету").title == "Похудеть на 5 кг")
        #expect(line("Пробежать полумарафон до конца лета").deadline == day(8, 31, 2027), "Лето 2026 уже кончилось")
        #expect(line("Выучить испанский за 3 месяца").deadline == day(12, 9))
        #expect(line("Выучить испанский за 3 месяца").title == "Выучить испанский")
        #expect(line("Открыть кофейню через полгода").deadline == day(3, 9, 2027))
        #expect(line("Открыть кофейню в 2027 году").deadline == day(12, 31, 2027))
        #expect(line("Открыть кофейню к 2027 году").deadline == day(12, 31))
        #expect(line("Сделать ремонт в этом году").deadline == day(12, 31))
        #expect(line("Сделать ремонт к Новому году").deadline == day(12, 31))
        #expect(line("Запустить бету через 2 недели").deadline == day(9, 23))
        #expect(line("Сдать отчёт на неделе").deadline == day(9, 13))
    }

    @Test("Не уверена — пусто: два срока на выбор, «за 4 часа» и «летом» — не сроки")
    func notDeadlines() {
        let choice = line("Переехать в ноябре или в декабре")
        #expect(choice.deadline == nil)
        #expect(choice.title == "Переехать в ноябре или в декабре")
        let marathon = line("Пробежать марафон за 4 часа")
        #expect(marathon.deadline == nil)
        #expect(marathon.title == "Пробежать марафон за 4 часа", "У цели нет длительности — слова остаются")
        #expect(line("Чаще гулять летом").deadline == nil)
        #expect(line("Когда-нибудь выучить японский").deadline == nil)
        #expect(line("Когда-нибудь выучить японский").priority == .low)
    }

    @Test("Важность и служебное: «Моя главная цель — …», «хочу», «важно»")
    func fillersAndImportance() {
        let main = line("Моя главная цель — запустить продукт до конца года")
        #expect(main.title == "Запустить продукт")
        #expect(main.priority == .important)
        #expect(main.deadline == day(12, 31))
        let wish = line("Хочу выучить английский, это важно")
        #expect(wish.title == "Выучить английский, это")
        #expect(wish.priority == .important)
        let plain = line("Развить личный бренд")
        #expect(plain.title == "Развить личный бренд")
        #expect(!plain.isUnderstood)
        #expect(line("Цель").title == "Цель", "Одно слово «цель» — это и есть название")
    }

    // MARK: Тип, сфера, чья

    @Test("Тип цели (goal_type): проект, измеримая, привычка, навык, развитие, другое")
    func kinds() {
        let classifier = GoalClassifier()
        func kind(_ title: String) -> GoalKind { classifier.classify(title: title).kind }
        #expect(kind("Выпустить Линия в TestFlight") == .project)
        #expect(kind("Получить 50 пользователей") == .measurable)
        #expect(kind("Пробежать 10 км") == .measurable)
        #expect(kind("Накопить 300 тысяч рублей") == .measurable)
        #expect(kind("Запустить бету на 50 пользователей") == .project, "Запуск с числом — проект, число будет рядом")
        #expect(kind("Бегать 3 раза в неделю") == .habit)
        #expect(kind("Медитировать каждый день") == .habit)
        #expect(kind("Бросить курить") == .habit)
        #expect(kind("Выучить испанский") == .skill)
        #expect(kind("Развить личный бренд") == .growth)
        #expect(kind("Стать спокойнее") == .growth)
        #expect(kind("Пробежать марафон") == .project)
        #expect(kind("Разобраться с налогами") == .other)
        #expect(classifier.classify(title: "Английский", details: "Хочу выучить для работы").kind == .skill)
    }

    @Test("Чья цель (scope): моя, команды, компании — по словам")
    func scopes() {
        let classifier = GoalClassifier()
        #expect(classifier.scope(title: "Довести выручку компании до 5 млн ₽ в месяц") == .company)
        #expect(classifier.scope(title: "Довести выручку до 5 млн ₽") == .company, "Выручка — цель компании")
        #expect(classifier.scope(title: "Запустить продукт всей командой") == .team)
        #expect(classifier.scope(title: "Закрыть квартал", details: "Вместе с коллегами из отдела продаж") == .team)
        #expect(classifier.scope(title: "Сделать ремонт вместе с женой") == .team, "Семья и партнёр — тоже команда")
        #expect(classifier.scope(title: "Съездить в отпуск всей семьёй") == .team)
        #expect(classifier.scope(title: "Выпустить Линия в TestFlight") == .personal)
        #expect(classifier.scope(title: "Сделать фирменный стиль") == .personal, "«Фирменный» — не фирма")
        #expect(classifier.scope(title: "Организовать свадьбу") == .personal)
        #expect(classifier.scope(title: "Позвонить другу") == .personal)
    }

    // MARK: Числа, этапы, метод

    @Test("Числа цели: что считаем — словами человека")
    func metrics() {
        func found(_ text: String) -> [String] {
            GoalMetricReader.metrics(in: text).map { "\(GoalProgressText.number($0.target))|\($0.unit)" }
        }
        #expect(found("Получить 50 пользователей") == ["50|пользователей"])
        #expect(found("Первые 100 платящих пользователей") == ["100|платящих пользователей"])
        #expect(found("Пробежать 10 км") == ["10|км"])
        #expect(found("Накопить 300 тысяч рублей") == ["300\u{00A0}000|рублей"])
        #expect(found("Накопить 300 000 ₽") == ["300\u{00A0}000|₽"])
        #expect(found("Поднять выручку на 20%") == ["20|%"])
        #expect(found("50 пользователей получили доступ") == ["50|пользователей"])
        #expect(found("Пятьдесят тестировщиков") == ["50|тестировщиков"])
        #expect(found("К 1 декабря выйти в App Store").isEmpty, "Дата — не число цели")
        #expect(found("Бегать 3 раза в неделю").isEmpty)
        #expect(found("в 2027 году").isEmpty)
        let range = GoalMetricReader.metrics(in: "Похудеть с 80 до 75 кг")
        #expect(range.map(\.start) == [80])
        #expect(range.map(\.target) == [75])
    }

    @Test("Пример заказчика из «Новой цели»: этап и число — «Этапы и числа»; стадия — из «Сейчас»")
    func structureFromStory() {
        let understanding = RuleBasedGoalAnalyzer().understand(GoalIntakeInput(
            title: "Запустить закрытую beta Linea",
            details: "У нас уже есть рабочий прототип приложения. Сейчас идёт переработка задач и онбординга. "
                + "Хотим, чтобы приложение было доступно через TestFlight и подключить 50 тестировщиков."
        ), profile: profile, time: time)
        #expect(understanding.method == .hybrid)
        #expect(understanding.milestones.map(\.title) == ["Приложение доступно через TestFlight"])
        #expect(understanding.metrics.map(\.unit) == ["тестировщиков"])
        #expect(understanding.metrics.first?.target == 50)
        #expect(understanding.metrics.first?.current == 0)
        #expect(understanding.stage == "Разработка", "«Прототип», «переработка» — разработка")
        #expect(understanding.scope == .personal)
        #expect(understanding.kind == .project)
    }

    @Test("Модель состояния из постановки: «прототип готов, перерабатывается механика» — разработка")
    func stageFromCurrentState() {
        let stage = GoalStages.current(
            kind: .project, title: "Запустить закрытую beta", details: nil,
            currentState: "Рабочий прототип готов. Календарь и HealthKit подключены. Сейчас перерабатывается механика задач и целей."
        )
        #expect(stage == "Разработка")
        let testing = GoalStages.current(kind: .project, title: "Выпустить приложение", details: nil,
                                         currentState: "Прототип готов, раздали бету тестировщикам")
        #expect(testing == "Тестирование", "Сказано о нескольких — последняя")
        let launch = GoalStages.current(kind: .project, title: "Выпустить приложение", details: nil,
                                        currentState: "Идёт работа")
        #expect(launch == nil, "«Идёт» — не «идея»: стадия не угадывается")
    }

    @Test("Стадии — свои у цели: бренд, язык, бег, поиск работы, по типу")
    func stageTemplates() {
        #expect(GoalStages.suggested(kind: .growth, title: "Развить личный бренд", details: nil)
            == ["Позиционирование", "Формирование регулярного контента", "Рост аудитории", "Монетизация"])
        #expect(GoalStages.suggested(kind: .skill, title: "Выучить испанский", details: nil)
            == ["Основы", "Регулярная практика", "Свободное общение"])
        #expect(GoalStages.suggested(kind: .project, title: "Пробежать марафон", details: nil).last == "Старт")
        #expect(GoalStages.suggested(kind: .project, title: "Найти новую работу", details: nil).last == "Оффер")
        #expect(GoalStages.suggested(kind: .habit, title: "Медитировать каждый день", details: nil)
            == ["Начало", "Формирование регулярности", "Привычка закрепилась"])
        #expect(GoalStages.suggested(kind: .other, title: "Разобраться с налогами", details: nil)
            == ["Начало", "Основная работа", "Завершение"])
    }

    @Test("Вес и старт из «Сейчас»: «вешу 82 кг» и цель «75 кг» — путь вниз")
    func metricStartFromCurrentState() {
        let understanding = RuleBasedGoalAnalyzer().understand(GoalIntakeInput(
            title: "Похудеть", details: "Сейчас вешу 82 кг, а нужно 75 кг к лету"
        ), profile: profile, time: time)
        let metric = understanding.metrics.first
        #expect(metric?.start == 82)
        #expect(metric?.current == 82)
        #expect(metric?.target == 75)
        #expect(metric?.isDecreasing == true)
        #expect(understanding.method == .metric)
        #expect(understanding.deadline == day(6, 1, 2027), "«к лету» в рассказе — тоже срок")

        let run = RuleBasedGoalAnalyzer().understand(GoalIntakeInput(title: "Пробежать 10 км", details: "Сейчас бегаю по 3 км"),
                                                     profile: profile, time: time)
        #expect(run.metrics.first?.start == 0)
        #expect(run.metrics.first?.current == 3)
        #expect(run.method == .metric)
    }

    @Test("Метод: что есть в словах, иначе — как обычно для типа")
    func methods() {
        func understood(_ title: String) -> GoalUnderstanding {
            RuleBasedGoalAnalyzer().understand(GoalIntakeInput(title: title), profile: profile, time: time)
        }
        #expect(understood("Получить 50 пользователей").method == .metric)
        #expect(understood("Запустить бету на 50 пользователей").method == .hybrid)
        #expect(understood("Развить личный бренд").method == .qualitative)
        #expect(understood("Медитировать каждый день").method == .qualitative)
        #expect(understood("Выучить испанский").method == .qualitative)
        #expect(understood("Разобраться с налогами").method == .manual)
        let manual = understood("Разобраться с налогами").goal(id: WowFixture.goalMVP, createdAt: time.now, time: time)
        #expect(manual.manualState == .started)
    }

    // MARK: Чипы

    @Test("Чип сильнее сказанного: срок, важность, прогресс, сфера")
    func chipsWin() {
        var draft = QuickGoalDraft(text: "Выпустить Линия в TestFlight до 15-го октября, важно")
        let said = resolve(draft)
        #expect(said.understanding.priority == .important)
        #expect(said.priorityOrigin == .typed)
        #expect(QuickGoalText.summary(said, time: time) == "до 15 октября · Высокая")

        draft.deadline = .at(day(11, 1))
        draft.priority = .low
        draft.method = .hybrid
        draft.scope = .team
        draft.ownerScope = "  сборки и TestFlight "  
        let chosen = resolve(draft)
        #expect(chosen.understanding.deadline == day(11, 1))
        #expect(chosen.deadlineOrigin == .chosen)
        #expect(chosen.understanding.priority == .low)
        #expect(chosen.understanding.method == .hybrid)
        #expect(chosen.methodOrigin == .chosen)
        #expect(chosen.scopeOrigin == .chosen)
        #expect(QuickGoalText.summary(chosen, time: time) == "до 1 ноября · Низкая · цель команды")
        let goal = chosen.goal(id: WowFixture.goalMVP, createdAt: time.now, time: time)
        #expect(goal.scope == .team, "Выбранное «От команды» хранится")
        #expect(goal.ownerScope == "Сборки и TestFlight")
        #expect(goal.priority == .low)
        #expect(goal.progressMethod == .hybrid)

        draft.deadline = .noDeadline
        let none = resolve(draft)
        #expect(none.understanding.deadline == nil)
        #expect(QuickGoalText.deadlineChip(none, time: time) == "Без срока")
    }

    @Test("Число в чипе прогресса и цель из одной строки")
    func measurableQuickGoal() {
        let resolution = resolve(QuickGoalDraft(text: "Получить 50 пользователей к 1 декабря"))
        #expect(resolution.title == "Получить 50 пользователей", "Число — часть цели, а не параметр")
        #expect(resolution.understanding.deadline == day(12, 1))
        #expect(QuickGoalText.methodChip(resolution) == "Число · 50 пользователей")
        let goal = resolution.goal(id: WowFixture.goalMVP, createdAt: time.now, time: time)
        let progress = GoalProgressEngine().progress(of: goal, tasks: [], time: time)
        #expect(GoalProgressText.summary(progress, time: time) == "0 из 50 пользователей · 0%")
        #expect(goal.metrics.first?.id != resolution.understanding.metrics.first?.id, "У этапов и чисел цели — свои id")
    }

    @Test("После «Изменить» этапы, числа и стадия — из исправленных слов; выбранный в чипе метод остаётся")
    func restructuredAfterEdit() {
        var understanding = RuleBasedGoalAnalyzer().understand(GoalIntakeInput(title: "Выпустить Линия в TestFlight"),
                                                               profile: profile, time: time)
        #expect(understanding.milestones.isEmpty)
        understanding.successCriteria = ["Сборка опубликована в TestFlight", "Подключить 50 тестировщиков"]
        understanding.currentState = "Прототип готов, раздали бету тестировщикам."
        let edited = understanding.restructured(methodChosen: false)
        #expect(edited.milestones.map(\.title) == ["Сборка опубликована в TestFlight"])
        #expect(edited.metrics.map(\.unit) == ["тестировщиков"])
        #expect(edited.method == .hybrid)
        #expect(edited.stage == "Тестирование")

        var manual = understanding
        manual.method = .manual
        #expect(manual.restructured(methodChosen: true).method == .manual)
    }

    @Test("Быстрые сроки в чипе: через месяц, через 3 месяца, до конца года")
    func deadlineOptions() {
        #expect(GoalDeadlineOption.inAMonth.date(time: time) == day(10, 9))
        #expect(GoalDeadlineOption.inThreeMonths.date(time: time) == day(12, 9))
        #expect(GoalDeadlineOption.endOfYear.date(time: time) == day(12, 31))
        #expect(QuickGoalText.deadlineOption(.inAMonth, time: time) == "Через месяц · 9 окт")
        #expect(QuickGoalText.deadlineOption(.endOfYear, time: time) == "До конца года · 31 дек")
    }

    @Test("Пустая строка цель не создаёт")
    func emptyLine() {
        #expect(!resolve(QuickGoalDraft(text: "   ")).canCreate)
        #expect(resolve(QuickGoalDraft(text: "Цель")).canCreate)
    }
}
