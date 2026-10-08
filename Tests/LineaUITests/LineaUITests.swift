//
//  LineaUITests.swift
//  LineaUITests
//
//  Проход по экранам на симуляторе iPhone, как это делал бы человек: «+»,
//  строка, чипы, маленькие выборы, карточка задачи, цель, «Сейчас». Каждый
//  шаг оставляет скриншот — CI (`.github/workflows/ios-ui.yml`) выгружает их
//  артефактом, чтобы интерфейс можно было посмотреть без Mac.
//
//  Приложение стартует с `-uiTesting`: данные только в памяти, каждый тест с
//  чистого листа, всё вводится через интерфейс. Часовой пояс тест выбирает
//  сам — такой, где сейчас около 11 утра: рабочий день идёт при любом часе
//  запуска CI. Язык и регион — русские, как у пользователя.
//
//  Запуск на Mac: схема LineaUITests, ⌘U.
//

import XCTest

final class LineaUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    // MARK: - 1. Быстрая задача

    @MainActor
    func test1QuickTaskFromAnyScreen() throws {
        let app = launch()
        snapshot(app, "01 Сегодня")

        let field = openQuickAdd(app)
        snapshot(app, "02 Быстрая задача — пусто")
        XCTAssertTrue(chip(app, "Когда: Без даты").exists, "«Когда?» не спрашиваем: по умолчанию — «Без даты»")
        XCTAssertTrue(chip(app, "Приоритет: Средний").exists, "Приоритет по умолчанию — «Средний»")
        XCTAssertFalse(app.buttons["Добавить задачу"].isEnabled, "Без названия добавлять нечего")

        field.tap()
        field.typeText("Купить продукты завтра на полчаса, важно")
        XCTAssertTrue(chip(app, "Когда: Завтра").waitForExistence(timeout: 5), "«завтра» должно встать в чип")
        XCTAssertTrue(chip(app, "Сколько займёт: ~30 мин").exists, "«на полчаса» — 30 минут")
        XCTAssertTrue(chip(app, "Приоритет: Высокий").exists, "«важно» — высокий приоритет")
        snapshot(app, "03 Строка разобрана в чипы")

        // Сохраняем задачу на сегодня, чтобы увидеть её в «Плане» этой недели.
        field.replaceText("Купить продукты сегодня на полчаса, важно")
        XCTAssertTrue(chip(app, "Когда: Сегодня").waitForExistence(timeout: 5))
        app.buttons["Добавить задачу"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "После «Добавить» лист закрывается")

        openTab(app, "План", index: 1)
        XCTAssertTrue(button(app, startingWith: "Купить продукты").waitForExistence(timeout: 5), "Задача в плане")
        XCTAssertFalse(element(app, labelContaining: "на полчаса").exists, "Распознанное уходит из названия")
        snapshot(app, "04 План после добавления")

        // «+ Задача» в «Плане» — тот же быстрый лист, а не форма.
        app.buttons["plan.addTask"].tap()
        XCTAssertTrue(titleField(app).waitForExistence(timeout: 5), "«+ Задача» открывает быстрый ввод")
        snapshot(app, "05 «+ Задача» из Плана")
    }

    // MARK: - 2. Чипы и маленькие выборы

    @MainActor
    func test2SmartChipsAndSelectors() throws {
        let app = launch()
        let field = openQuickAdd(app)
        field.tap()
        field.typeText("Отчёт")

        chip(app, "Когда:").tap()
        for option in ["Сегодня", "Завтра", "На неделе", "Выбрать дату…", "Срок…", "Без даты"] {
            XCTAssertTrue(app.buttons[option].waitForExistence(timeout: 5), "В меню «Когда» нет «\(option)»")
        }
        snapshot(app, "06 Меню «Когда»")
        app.buttons["Завтра"].tap()
        XCTAssertTrue(chip(app, "Когда: Завтра").waitForExistence(timeout: 5))

        chip(app, "Когда:").tap()
        app.buttons["Выбрать дату…"].tap()
        let calendar = app.datePickers.firstMatch
        XCTAssertTrue(calendar.waitForExistence(timeout: 5), "«Выбрать дату…» открывает календарь")
        snapshot(app, "07 Выбрать дату — календарь")
        // День в календаре подписан по-разному на разных языках, число — всегда.
        let today = calendar.buttons.matching(NSPredicate(format: "label MATCHES %@", Self.dayPattern(daysFromNow: 0))).firstMatch
        if today.exists {
            today.tap()
            XCTAssertTrue(chip(app, "Когда: Сегодня").waitForExistence(timeout: 5), "Тап по дню выбирает его и закрывает календарь")
        } else {
            XCTFail("В календаре не нашёлся сегодняшний день")
            dismissPopover(app)
        }

        chip(app, "Когда:").tap()
        app.buttons["Срок…"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5), "«Срок…» открывает дату и время")
        snapshot(app, "08 Срок — дата и время")
        app.buttons["quickAdd.deadline.done"].tap()
        XCTAssertTrue(chip(app, "Когда: Сегодня, до 18:00").waitForExistence(timeout: 5), "Срок по умолчанию — 18:00 дня задачи")

        chip(app, "Когда:").tap()
        app.buttons["На неделе"].tap()
        // Названный срок сильнее недели: в чипе — он.
        XCTAssertTrue(chip(app, "Когда: до 18:00").waitForExistence(timeout: 5))

        chip(app, "Сколько займёт:").tap()
        for option in ["15 мин", "30 мин", "45 мин", "1 час", "Другое…"] {
            XCTAssertTrue(app.buttons[option].waitForExistence(timeout: 5), "В меню длительности нет «\(option)»")
        }
        snapshot(app, "09 Меню длительности")
        app.buttons["Другое…"].tap()
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 5), "«Другое…» открывает колесо")
        wheel.adjust(toPickerWheelValue: "1 ч 30 мин")
        snapshot(app, "10 Своя длительность — колесо")
        app.buttons["quickAdd.minutes.done"].tap()
        XCTAssertTrue(chip(app, "Сколько займёт: ~1 ч 30 мин").waitForExistence(timeout: 5))

        chip(app, "Приоритет:").tap()
        for option in ["Низкий", "Средний", "Высокий"] {
            XCTAssertTrue(app.buttons[option].waitForExistence(timeout: 5), "В меню приоритета нет «\(option)»")
        }
        app.buttons["Низкий"].tap()
        XCTAssertTrue(chip(app, "Приоритет: Низкий").waitForExistence(timeout: 5))
        snapshot(app, "11 Чипы после выбора")

        let chips = ["Когда:", "Сколько займёт:", "Приоритет:", "Цель", "Похоже, к цели"]
            .map { app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", $0)).count }
            .reduce(0, +)
        XCTAssertLessThanOrEqual(chips, 4, "Не больше четырёх чипов")

        app.buttons["Добавить задачу"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "После «Добавить» лист закрывается")
        openTab(app, "План", index: 1)
        XCTAssertTrue(button(app, startingWith: "Отчёт").waitForExistence(timeout: 5))
        snapshot(app, "12 План: задача без дня со сроком")
    }

    // MARK: - 3. Цель: важность, подсказка «Похоже, относится к», явная связь

    @MainActor
    func test3GoalImportanceAndLinking() throws {
        let app = launch()
        openTab(app, "План", index: 1)
        createGoal(app, "Запустить Линия Beta",
                   details: "Есть прототип приложения, идёт переработка онбординга. Хотим выпустить бету через TestFlight.")
        let goalRow = button(app, startingWith: "Запустить Линия Beta")
        XCTAssertTrue(goalRow.waitForExistence(timeout: 5), "Цель в плане")

        // Важность — в карточке цели.
        goalRow.tap()
        XCTAssertTrue(app.buttons["Высокая"].waitForExistence(timeout: 5), "В карточке цели есть «Важность»")
        app.buttons["Высокая"].tap()
        snapshot(app, "13 Карточка цели: важность")
        app.navigationBars.buttons["Готово"].tap()
        XCTAssertTrue(app.buttons["Высокая"].waitForNonExistence(timeout: 5))

        // Пример заказчика: общих слов с целью нет, а связь Linea видит.
        let field = openQuickAdd(app)
        field.tap()
        field.typeText("Опубликовать сборку в TestFlight")
        let suggestion = app.staticTexts["goalSuggestion.title"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5), "Linea подсказывает вероятную цель")
        XCTAssertEqual(suggestion.label, "Запустить Линия Beta")
        XCTAssertTrue(app.staticTexts["Похоже, относится к:"].exists)
        XCTAssertTrue(chip(app, "Цель не выбрана").exists, "Подсказка не связывает сама")
        snapshot(app, "14 Похоже, относится к цели")
        app.buttons["goalSuggestion.link"].tap()
        XCTAssertTrue(chip(app, "Цель: Запустить Линия Beta").waitForExistence(timeout: 5), "«Связать» ставит цель")
        XCTAssertFalse(app.staticTexts["goalSuggestion.title"].exists, "Связано — подсказки больше нет")
        snapshot(app, "15 Связано")
        app.buttons["Добавить задачу"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))

        // Ничего не нажал — задача спокойно живёт без цели.
        let ignored = openQuickAdd(app)
        ignored.tap()
        ignored.typeText("Проверить онбординг сегодня")
        XCTAssertTrue(app.staticTexts["goalSuggestion.title"].waitForExistence(timeout: 5), "Онбординг — из рассказа о цели")
        app.buttons["Добавить задачу"].tap()
        XCTAssertTrue(ignored.waitForNonExistence(timeout: 5))

        let explicit = openQuickAdd(app)
        explicit.tap()
        explicit.typeText("Подготовить релиз для цели Beta")
        XCTAssertTrue(chip(app, "Цель: Запустить Линия Beta").waitForExistence(timeout: 5), "«для цели …» связывает сразу")
        snapshot(app, "16 Цель названа словами")
        app.buttons["Добавить задачу"].tap()
        XCTAssertTrue(explicit.waitForNonExistence(timeout: 5))

        openTab(app, "План", index: 1)
        XCTAssertTrue(button(app, startingWith: "Подготовить релиз").waitForExistence(timeout: 5))
        let check = button(app, startingWith: "Проверить онбординг")
        XCTAssertTrue(check.waitForExistence(timeout: 5), "Задача без цели — на месте")
        snapshot(app, "17 План с целью")

        // В карточке задачи без цели подсказка та же — и тоже ничего не решает сама.
        bringAboveCommandBar(check, in: app)
        check.tap()
        XCTAssertTrue(app.navigationBars["Задача"].waitForExistence(timeout: 5))
        let noGoal = app.buttons.matching(NSPredicate(format: "label == %@ AND isSelected == true", "Без цели")).firstMatch
        XCTAssertTrue(noGoal.exists, "Задача сохранена без цели")
        XCTAssertTrue(app.staticTexts["goalSuggestion.title"].exists, "Карточка тоже подсказывает цель")
        snapshot(app, "17a Карточка: похоже, относится к цели")
        app.navigationBars["Задача"].buttons["Отмена"].tap()
    }

    // MARK: - 4. Карточка: тип задачи и «Сначала нужно»

    @MainActor
    func test4TaskCardKindAndDependencies() throws {
        let app = launch()
        addTask(app, "Собрать данные сегодня")
        addTask(app, "Написать отчёт сегодня, важно")

        openTab(app, "План", index: 1)
        let report = button(app, startingWith: "Написать отчёт")
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        report.tap()
        XCTAssertTrue(app.navigationBars["Задача"].waitForExistence(timeout: 5), "Тап по задаче открывает карточку")
        app.swipeUp()
        let kind = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Тип задачи")).firstMatch
        XCTAssertTrue(kind.waitForExistence(timeout: 5), "Внизу карточки — тип задачи")
        XCTAssertEqual(kind.label, "Тип задачи: Обязательство")
        let addBlocker = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "без которой не начать")).firstMatch
        XCTAssertTrue(addBlocker.exists, "В карточке есть «Сначала нужно»")
        snapshot(app, "18 Карточка: тип и «Сначала нужно»")

        addBlocker.tap()
        // Строка задачи в «Плане» под карточкой подписана так же, но нажать на неё нельзя.
        tapMenuItem(app, "Собрать данные")
        XCTAssertTrue(app.buttons["Убрать «Собрать данные»"].waitForExistence(timeout: 5))
        snapshot(app, "19 Зависимость добавлена")
        app.navigationBars.buttons["Готово"].tap()

        openTab(app, "Сегодня", index: 0)
        let first = button(app, containing: "Собрать данные")
        let second = button(app, containing: "Написать отчёт")
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        XCTAssertLessThan(first.frame.minY, second.frame.minY, "Отчёт в плане после данных, хотя важнее")
        scrollTo(second, in: app)
        snapshot(app, "20 Сегодня: отчёт после данных")
    }

    // MARK: - 5. «Сейчас»: пример из постановки

    @MainActor
    func test5NowBeforeMeeting() throws {
        let app = launch()
        addTask(app, "Встреча с клиентом в \(Self.clock(minutesFromNow: 25)) на 30 минут")
        addTask(app, "Подготовить стратегию сегодня на полтора часа, важно")
        addTask(app, "Ответить на письма сегодня 15 минут")

        openTab(app, "Сегодня", index: 0)
        let now = nowCard(app)
        XCTAssertTrue(now.waitForExistence(timeout: 15), "На «Сегодня» есть «Сейчас»")
        XCTAssertTrue(now.staticTexts["Ответить на письма"].exists, "До встречи 25 минут — сейчас короткое дело")
        let reason = now.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "лучше после встречи")).firstMatch
        XCTAssertTrue(reason.exists, "Стратегия — после встречи")
        XCTAssertTrue(reason.label.hasPrefix("До встречи "), reason.label)
        XCTAssertTrue(reason.label.hasSuffix("— на это хватит, а «Подготовить стратегию» лучше после встречи."), reason.label)
        XCTAssertFalse(reason.label.dropLast().contains("."), "Причина — одно предложение: \(reason.label)")
        XCTAssertTrue(now.buttons["Начать"].exists)
        scrollTo(now, in: app)
        snapshot(app, "21 Сейчас: короткое дело до встречи")
    }

    // MARK: - 7. Одно действие: «Начать», «Другое», «Готово»

    @MainActor
    func test7NowStartOtherDone() throws {
        let app = launch()
        addTask(app, "Ответить клиенту сегодня 15 минут, важно")
        addTask(app, "Проверить сборку сегодня 15 минут")
        addTask(app, "Разобрать письмо сегодня 10 минут")
        addTask(app, "Оплатить интернет сегодня 10 минут")

        openTab(app, "Сегодня", index: 0)
        let now = nowCard(app)
        XCTAssertTrue(now.waitForExistence(timeout: 15))
        XCTAssertTrue(now.staticTexts["Ответить клиенту"].waitForExistence(timeout: 5), "Важное и короткое — первым")
        XCTAssertTrue(now.staticTexts["~15 мин"].exists)
        XCTAssertTrue(now.staticTexts["Высокий приоритет — лучше не откладывать."].exists, "У рекомендации есть причина")
        scrollTo(now, in: app)
        snapshot(app, "24 Сейчас: одно действие")

        now.buttons["Другое"].tap()
        XCTAssertTrue(now.staticTexts["Можно ещё:"].waitForExistence(timeout: 5))
        let options = now.buttons.matching(NSPredicate(format: "label CONTAINS %@", "мин"))
        XCTAssertLessThanOrEqual(options.count, 3, "Не больше трёх вариантов")
        XCTAssertGreaterThanOrEqual(options.count, 2)
        scrollTo(options.element(boundBy: options.count - 1), in: app)
        snapshot(app, "25 Другое: два-три варианта")
        let chosen = now.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Проверить сборку")).firstMatch
        XCTAssertTrue(chosen.exists)
        chosen.tap()
        XCTAssertTrue(now.staticTexts["Проверить сборку"].waitForExistence(timeout: 5), "Выбранное стало «сейчас»")
        XCTAssertTrue(now.staticTexts["Короткая — можно закрыть сразу."].exists, "У выбранного — своя причина")

        now.buttons["Начать"].tap()
        XCTAssertTrue(now.buttons["Готово"].waitForExistence(timeout: 10), "Начатое — «в работе» с «Готово»")
        XCTAssertTrue(now.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Начато в")).firstMatch.exists)
        scrollTo(now, in: app)
        snapshot(app, "26 В работе")

        now.buttons["Готово"].tap()
        XCTAssertTrue(now.buttons["Начать"].waitForExistence(timeout: 10), "После «Готово» — следующее действие")
        XCTAssertFalse(now.staticTexts["Проверить сборку"].exists)
        snapshot(app, "27 Следующее действие")
    }

    // MARK: - 8. «Без даты»: без вопроса «Когда?», список и разбор

    @MainActor
    func test8InboxWithoutDate() throws {
        let app = launch()
        let field = openQuickAdd(app)
        field.tap()
        field.typeText("Посмотреть новые AI-модели")
        XCTAssertTrue(chip(app, "Когда: Без даты").waitForExistence(timeout: 5), "«Когда?» не спрашиваем")
        snapshot(app, "28 Без даты — сразу «Добавить»")
        app.buttons["Добавить задачу"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "Одного названия достаточно")
        addTask(app, "Написать Саше")
        addTask(app, "Изучить новый API")

        openTab(app, "План", index: 1)
        let inbox = app.descendants(matching: .any).matching(identifier: "plan.inbox").firstMatch
        XCTAssertTrue(inbox.waitForExistence(timeout: 5), "В «Плане» есть «Без даты»")
        for title in ["Посмотреть новые AI-модели", "Написать Саше", "Изучить новый API"] {
            XCTAssertTrue(inbox.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch.exists,
                          "«\(title)» — в «Без даты»")
        }
        snapshot(app, "29 План: Без даты")

        openTab(app, "Сегодня", index: 0)
        let offer = app.descendants(matching: .any).matching(identifier: "today.inbox").firstMatch
        XCTAssertTrue(offer.waitForExistence(timeout: 10), "Три задачи без даты — Linea предлагает разобрать")
        XCTAssertTrue(offer.staticTexts["3 задачи без даты — разберём за минуту?"].exists)
        scrollTo(offer, in: app)
        snapshot(app, "30 Сегодня: предложение разобрать")
        offer.buttons["Разобрать"].tap()

        let title = app.staticTexts.matching(identifier: "inbox.title").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Разбор открылся")
        XCTAssertEqual(title.label, "Посмотреть новые AI-модели", "Давние — первыми")
        XCTAssertTrue(app.staticTexts["1 из 3"].exists)
        XCTAssertTrue(app.staticTexts.matching(identifier: "inbox.suggestion").firstMatch.exists, "Linea подсказывает, куда")
        snapshot(app, "31 Разбор: первая задача")
        app.buttons["inbox.choice.today"].tap()
        XCTAssertTrue(app.staticTexts["2 из 3"].waitForExistence(timeout: 5))
        snapshot(app, "32 Разбор: вторая задача")
        app.buttons["inbox.choice.keep"].tap()
        XCTAssertTrue(app.staticTexts["3 из 3"].waitForExistence(timeout: 5))
        app.buttons["inbox.delete"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "Разобрали последнюю — лист закрылся")
        XCTAssertTrue(offer.waitForNonExistence(timeout: 5), "Разобрано — предложения больше нет")

        openTab(app, "План", index: 1)
        XCTAssertTrue(inbox.waitForExistence(timeout: 5))
        XCTAssertTrue(inbox.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Написать Саше")).firstMatch.exists,
                      "Оставленная — в «Без даты»")
        XCTAssertFalse(inbox.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Посмотреть новые AI-модели")).firstMatch.exists,
                       "Отправленная на сегодня ушла из «Без даты»")
        XCTAssertFalse(element(app, labelContaining: "Изучить новый API").exists, "Удалённой нет")
        XCTAssertTrue(button(app, startingWith: "Посмотреть новые AI-модели").exists, "Она — в дне")
        snapshot(app, "33 План после разбора")
    }

    // MARK: - 9. Новая цель: сначала понять, потом создать

    @MainActor
    func test9GoalIntake() throws {
        let app = launch()
        openTab(app, "План", index: 1)
        app.buttons["plan.addGoal"].tap()
        let title = field(app, "goal.title")
        XCTAssertTrue(title.waitForExistence(timeout: 5), "«+ Цель» открывает «Новая цель»")
        XCTAssertTrue(app.staticTexts["Чего хочешь достичь?"].exists)
        XCTAssertTrue(app.staticTexts["Что уже сделано, где ты сейчас и что будет означать, что цель достигнута?"].exists)
        XCTAssertTrue(app.buttons["goal.voice"].exists, "Можно рассказать голосом")
        XCTAssertFalse(app.buttons["goal.continue"].isEnabled, "Без названия продолжать нечего")
        title.tap()
        title.typeText("Запустить закрытую beta Linea")
        let details = field(app, "goal.details")
        details.tap()
        details.typeText("У нас уже есть рабочий прототип приложения. Сейчас идёт переработка задач и онбординга. "
            + "Хотим, чтобы приложение было доступно через TestFlight и подключить 50 тестировщиков.")
        snapshot(app, "34 Новая цель: название и рассказ")
        app.buttons["goal.continue"].tap()

        let review = app.descendants(matching: .any).matching(identifier: "goal.review").firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 5), "Linea показывает, как поняла цель, — без вопросов")
        XCTAssertTrue(app.staticTexts["Я поняла цель так"].exists)
        XCTAssertEqual(app.staticTexts["goal.review.title"].label, "Запустить закрытую beta Linea")
        XCTAssertEqual(app.staticTexts["goal.review.current"].label,
                       "Уже есть рабочий прототип приложения. Идёт переработка задач и онбординга.")
        XCTAssertEqual(app.staticTexts["goal.review.target"].label,
                       "Приложение доступно через TestFlight и подключить 50 тестировщиков.")
        snapshot(app, "35 Я поняла цель так")

        app.buttons["goal.change"].tap()
        XCTAssertTrue(field(app, "goal.edit.title").waitForExistence(timeout: 5), "«Изменить» открывает правку")
        snapshot(app, "36 Изменить")
        app.buttons["goal.edit.done"].tap()
        XCTAssertTrue(app.buttons["goal.confirm"].waitForExistence(timeout: 5), "После правки — снова «Я поняла цель так»")
        app.buttons["goal.confirm"].tap()
        XCTAssertTrue(app.buttons["goal.confirm"].waitForNonExistence(timeout: 5), "«Всё верно» создаёт цель")
        XCTAssertTrue(button(app, startingWith: "Запустить закрытую beta Linea").waitForExistence(timeout: 5), "Цель в плане")

        // Одна строка — Linea задаёт один вопрос, потом следующий.
        app.buttons["plan.addGoal"].tap()
        let short = field(app, "goal.title")
        XCTAssertTrue(short.waitForExistence(timeout: 5))
        short.tap()
        short.typeText("Запустить продукт")
        app.buttons["goal.continue"].tap()
        let resultQuestion = app.staticTexts["Как поймём, что цель достигнута?"]
        XCTAssertTrue(resultQuestion.waitForExistence(timeout: 5), "Не хватает результата — Linea спрашивает")
        XCTAssertEqual(app.staticTexts.matching(identifier: "goal.question").count, 1, "Один вопрос за раз")
        XCTAssertFalse(review.exists, "Цель не показана, пока не понятна")
        snapshot(app, "37 Один вопрос")
        let answer = field(app, "goal.answer")
        answer.tap()
        answer.typeText("Первые 100 платящих пользователей")
        app.buttons["goal.answer.continue"].tap()
        XCTAssertTrue(app.staticTexts["С чего начинаем — что уже есть?"].waitForExistence(timeout: 5), "Следующий вопрос — после ответа")
        app.buttons["goal.skip"].tap()
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["goal.review.target"].label, "Первые 100 платящих пользователей.")
        snapshot(app, "38 Понятая цель после ответа")
        app.buttons["goal.confirm"].tap()
        XCTAssertTrue(button(app, startingWith: "Запустить продукт").waitForExistence(timeout: 5))

        // Карточка цели хранит, как Linea её поняла.
        button(app, startingWith: "Запустить закрытую beta Linea").tap()
        XCTAssertTrue(app.navigationBars["Цель"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Результат"].exists)
        snapshot(app, "39 Карточка цели: как Linea её поняла")
    }

    // MARK: - 10. Свайпы и долгое нажатие: главное — без карточки задачи

    @MainActor
    func test10SwipeAndLongPress() throws {
        let app = launch()
        openTab(app, "План", index: 1)
        createGoal(app, "Запустить MVP Linea", details: "Есть прототип. Хочу выпустить первую версию в TestFlight.")
        addTask(app, "Купить молоко сегодня")
        addTask(app, "Позвонить маме сегодня")
        addTask(app, "Подготовить релиз сегодня")
        openTab(app, "План", index: 1)

        // Вправо — «Готово».
        let milk = button(app, startingWith: "Купить молоко")
        XCTAssertTrue(milk.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Отметить невыполненной"].exists)
        bringAboveCommandBar(milk, in: app)
        milk.swipeRight()
        XCTAssertTrue(app.buttons["Отметить невыполненной"].waitForExistence(timeout: 5), "Свайп вправо закрывает задачу")
        XCTAssertFalse(app.navigationBars["Задача"].exists, "Карточка задачи не открывалась")
        snapshot(app, "40 Свайп вправо — Готово")

        // Влево — «Перенести»: короткий выбор; «Без даты» — во входящие.
        let mom = button(app, startingWith: "Позвонить маме")
        bringAboveCommandBar(mom, in: app)
        mom.swipeLeft()
        XCTAssertTrue(app.staticTexts["Перенести «Позвонить маме»"].waitForExistence(timeout: 5), "Свайп влево — «Перенести»")
        for option in ["Завтра", "Выбрать дату…", "Без даты"] {
            XCTAssertTrue(app.buttons[option].exists, "В «Перенести» есть «\(option)»")
        }
        snapshot(app, "41 Свайп влево — Перенести")
        app.buttons["Без даты"].tap()
        let inbox = app.descendants(matching: .any).matching(identifier: "plan.inbox").firstMatch
        XCTAssertTrue(inbox.waitForExistence(timeout: 5), "Появился раздел «Без даты»")
        XCTAssertTrue(inbox.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Позвонить маме")).firstMatch
            .waitForExistence(timeout: 5), "Задача перенесена в «Без даты»")

        // «Выбрать дату…» — календарь.
        let release = button(app, startingWith: "Подготовить релиз")
        bringAboveCommandBar(release, in: app)
        release.swipeLeft()
        let pickDay = app.buttons["Выбрать дату…"]
        XCTAssertTrue(pickDay.waitForExistence(timeout: 5))
        pickDay.tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5), "«Выбрать дату…» открывает календарь")
        snapshot(app, "42 Перенести — свой день")
        app.navigationBars["Перенести"].buttons["Отмена"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForNonExistence(timeout: 5))

        // Долгое нажатие — меню задачи.
        bringAboveCommandBar(release, in: app)
        release.press(forDuration: 1.2)
        for item in ["Изменить", "Привязать к цели", "Изменить приоритет", "Удалить"] {
            XCTAssertTrue(app.buttons[item].waitForExistence(timeout: 5), "В меню есть «\(item)»")
        }
        snapshot(app, "43 Долгое нажатие — меню")
        app.buttons["Изменить приоритет"].tap()
        tapMenuItem(app, "Высокий")
        XCTAssertTrue(app.staticTexts["Высокий"].waitForExistence(timeout: 5), "Приоритет сменился без карточки")

        bringAboveCommandBar(release, in: app)
        release.press(forDuration: 1.2)
        let linkGoal = app.buttons["Привязать к цели"]
        XCTAssertTrue(linkGoal.waitForExistence(timeout: 5))
        linkGoal.tap()
        tapMenuItem(app, "Запустить MVP Linea")

        bringAboveCommandBar(release, in: app)
        release.press(forDuration: 1.2)
        let edit = app.buttons["Изменить"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.navigationBars["Задача"].waitForExistence(timeout: 5), "«Изменить» открывает карточку")
        let linked = app.buttons.matching(NSPredicate(format: "label == %@ AND isSelected == true", "Запустить MVP Linea")).firstMatch
        XCTAssertTrue(linked.exists, "Задача привязана к цели из меню")
        snapshot(app, "44 Карточка: цель и приоритет из меню")
        app.navigationBars["Задача"].buttons["Отмена"].tap()
        XCTAssertTrue(app.navigationBars["Задача"].waitForNonExistence(timeout: 5))

        bringAboveCommandBar(milk, in: app)
        milk.press(forDuration: 1.2)
        let delete = app.buttons["Удалить"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(button(app, startingWith: "Купить молоко").waitForNonExistence(timeout: 5), "«Удалить» из меню")

        // «Сегодня»: те же жесты у задачи в «Дальше».
        openTab(app, "Сегодня", index: 0)
        let planned = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Подготовить релиз", "мин"))
            .firstMatch
        XCTAssertTrue(planned.waitForExistence(timeout: 10), "Задача в «Дальше»")
        scrollTo(planned, in: app)
        bringAboveCommandBar(planned, in: app)
        planned.swipeRight()
        openTab(app, "План", index: 1)
        XCTAssertTrue(app.buttons["Отметить невыполненной"].waitForExistence(timeout: 5), "Свайп на «Сегодня» закрыл задачу")
        snapshot(app, "45 План после свайпа на «Сегодня»")
    }

    // MARK: - 11. AI-разбор: пример заказчика

    @MainActor
    func test11UnderstoodTask() throws {
        let app = launch()
        let field = openQuickAdd(app)
        field.tap()
        field.typeText("Завтра до обеда подготовить КП для клиента, часа на полтора, высокий приоритет.")
        XCTAssertTrue(chip(app, "Когда: Завтра, до 12:00").waitForExistence(timeout: 5), "«Завтра до обеда» — завтра до 12:00")
        XCTAssertTrue(chip(app, "Сколько займёт: ~1 ч 30 мин").exists, "«часа на полтора» — 1 ч 30 мин")
        XCTAssertTrue(chip(app, "Приоритет: Высокий").exists, "«высокий приоритет» — высокий")
        let title = app.staticTexts["quickAdd.understood.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Linea показывает, как поняла задачу")
        XCTAssertEqual(title.label, "Подготовить КП для клиента")
        XCTAssertEqual(app.staticTexts["quickAdd.understood.summary"].label, "Завтра · до 12:00 · ~1 ч 30 мин · Высокий")
        snapshot(app, "46 AI-разбор: пример заказчика")

        // Не уверена — пусто: два дня на выбор и «вечером» не становятся датой.
        field.replaceText("Позвонить маме завтра или послезавтра вечером")
        XCTAssertTrue(chip(app, "Когда: Без даты").waitForExistence(timeout: 5), "Два дня на выбор — дня нет")
        XCTAssertFalse(app.staticTexts["quickAdd.understood.title"].exists, "Понимать нечего — подсказки нет")
        snapshot(app, "47 Не уверена — пусто")

        // На сегодня, чтобы задача была в «Плане» этой недели.
        field.replaceText("Сегодня до обеда подготовить КП для клиента, часа на полтора, высокий приоритет.")
        XCTAssertTrue(chip(app, "Когда: Сегодня, до 12:00").waitForExistence(timeout: 5))
        app.buttons["Добавить задачу"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))

        openTab(app, "План", index: 1)
        let row = button(app, startingWith: "Подготовить КП для клиента")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Задача в плане под своим названием")
        XCTAssertTrue(row.label.contains("до 12:00 · ~1 ч 30 мин"), "Под задачей — что задано: \(row.label)")
        XCTAssertTrue(app.staticTexts["Высокий"].exists, "Сказанный приоритет — у задачи")
        snapshot(app, "48 План: задача после разбора")

        // Человек меняет приоритет руками — дальше задача остаётся такой.
        row.tap()
        XCTAssertTrue(app.navigationBars["Задача"].waitForExistence(timeout: 5))
        app.buttons["Средний"].tap()
        app.navigationBars.buttons["Готово"].tap()
        XCTAssertTrue(app.navigationBars["Задача"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Высокий"].waitForNonExistence(timeout: 5), "Приоритет человека сохранился")
        snapshot(app, "49 План: приоритет поменян руками")
    }

    // MARK: - 6. Длительность по типу задачи

    @MainActor
    func test6DurationByKind() throws {
        let app = launch()
        let field = openQuickAdd(app)
        field.tap()
        field.typeText("Ответить Ивану")
        XCTAssertTrue(chip(app, "Сколько займёт: ~15 мин").waitForExistence(timeout: 5), "Входящее — 15 минут")
        snapshot(app, "22 Входящее — 15 минут")
        field.replaceText("Подготовить стратегию")
        XCTAssertTrue(chip(app, "Сколько займёт: ~1 ч").waitForExistence(timeout: 5), "Шаг к цели — час")
        snapshot(app, "23 Шаг к цели — час")
    }

    // MARK: - Запуск

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launchEnvironment["TZ"] = Self.zoneIdentifier
        app.launch()
        XCTAssertTrue(app.buttons["Новая задача"].waitForExistence(timeout: 20), "Приложение не открылось")
        return app
    }

    /// Пояс, где сейчас около 11 утра: рабочий день (9–21) при любом часе запуска.
    static let zoneIdentifier: String = {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var offset = 11 - utc.component(.hour, from: Date())
        if offset < -12 { offset += 24 }
        if offset > 14 { offset -= 24 }
        if offset == 0 { return "Etc/GMT" }
        // В Etc/GMT знак наоборот: Etc/GMT-3 — это UTC+3.
        return offset > 0 ? "Etc/GMT-\(offset)" : "Etc/GMT+\(-offset)"
    }()

    static var appTimeZone: TimeZone { TimeZone(identifier: zoneIdentifier)! }

    /// «11:35» в поясе приложения через `minutes` минут.
    static func clock(minutesFromNow minutes: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = appTimeZone
        let moment = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let parts = calendar.dateComponents([.hour, .minute], from: moment)
        return String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// Подпись дня в календаре содержит его число отдельным словом:
    /// «пятница, 2 октября» или «Friday, October 2».
    static func dayPattern(daysFromNow days: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = appTimeZone
        let day = calendar.component(.day, from: Date().addingTimeInterval(TimeInterval(days * 86_400)))
        return ".*(^|[^0-9])\(day)([^0-9]|$).*"
    }

    // MARK: - Шаги

    @MainActor
    private func openQuickAdd(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["Новая задача"].firstMatch.tap()
        let field = titleField(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Лист быстрой задачи не открылся")
        return field
    }

    @MainActor
    private func addTask(_ app: XCUIApplication, _ text: String) {
        let field = openQuickAdd(app)
        field.tap()
        field.typeText(text)
        let add = app.buttons["Добавить задачу"]
        XCTAssertTrue(add.isEnabled)
        add.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "«\(text)» не добавилась")
    }

    @MainActor
    private func titleField(_ app: XCUIApplication) -> XCUIElement {
        let byID = app.descendants(matching: .any).matching(identifier: "quickAdd.title").firstMatch
        if byID.exists { return byID }
        let view = app.textViews.firstMatch
        return view.exists ? view : app.textFields.firstMatch
    }

    /// Вкладка внизу. Нажатие во время закрытия листа теряется — проверяем,
    /// что вкладка выбрана, и при необходимости нажимаем ещё раз.
    @MainActor
    private func openTab(_ app: XCUIApplication, _ name: String, index: Int) {
        let named = app.tabBars.buttons[name]
        let tab = named.waitForExistence(timeout: 3) ? named : app.tabBars.buttons.element(boundBy: index)
        for _ in 0..<3 {
            tab.tap()
            let selected = NSPredicate(format: "isSelected == true")
            let expectation = XCTNSPredicateExpectation(predicate: selected, object: tab)
            if XCTWaiter().wait(for: [expectation], timeout: 2) == .completed { return }
        }
        XCTFail("Вкладка «\(name)» не открылась")
    }

    /// Пункт открывшегося меню. Меню появляется с анимацией, а элемент с той
    /// же подписью может быть и под ним (строка списка) — ждём нажимаемый.
    @MainActor
    private func tapMenuItem(_ app: XCUIApplication, _ label: String) {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", label))
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let item = matches.allElementsBoundByIndex.last(where: { $0.isHittable }) {
                item.tap()
                return
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTFail("В меню нет пункта «\(label)»")
    }

    /// Строка выше строки ассистента: низ экрана перекрыт ею и вкладками, и
    /// жест по строке под ними попал бы в них.
    @MainActor
    private func bringAboveCommandBar(_ element: XCUIElement, in app: XCUIApplication) {
        let bar = app.buttons["Новая задача"].firstMatch
        var attempts = 0
        while element.exists, bar.exists, element.frame.maxY > bar.frame.minY - 12, attempts < 4 {
            app.swipeUp()
            attempts += 1
        }
    }

    @MainActor
    private func dismissPopover(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while !element.isHittable, attempts < 5 {
            app.swipeUp()
            attempts += 1
        }
    }

    /// «+ Цель» → название и рассказ → «Я поняла цель так» → «Всё верно».
    @MainActor
    private func createGoal(_ app: XCUIApplication, _ title: String, details: String) {
        app.buttons["plan.addGoal"].tap()
        let titleInput = field(app, "goal.title")
        XCTAssertTrue(titleInput.waitForExistence(timeout: 5), "«Новая цель» не открылась")
        titleInput.tap()
        titleInput.typeText(title)
        let detailsInput = field(app, "goal.details")
        detailsInput.tap()
        detailsInput.typeText(details)
        app.buttons["goal.continue"].tap()
        let confirm = app.buttons["goal.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Linea не показала, как поняла цель")
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5), "Цель не создалась")
    }

    // MARK: - Поиск

    /// Поле ввода по идентификатору — каким бы элементом его ни показала система.
    @MainActor
    private func field(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let byID = app.descendants(matching: .any).matching(identifier: identifier)
        let input = byID.matching(NSPredicate(format: "elementType == %d OR elementType == %d",
                                              XCUIElement.ElementType.textField.rawValue,
                                              XCUIElement.ElementType.textView.rawValue)).firstMatch
        return input.waitForExistence(timeout: 5) ? input : byID.firstMatch
    }

    @MainActor
    private func nowCard(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "today.now").firstMatch
    }

    @MainActor
    private func chip(_ app: XCUIApplication, _ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    @MainActor
    private func button(_ app: XCUIApplication, startingWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    @MainActor
    private func button(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func element(_ app: XCUIApplication, labelContaining text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    // MARK: - Скриншоты

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension XCUIElement {
    /// Стереть набранное и ввести своё. Поле уже в фокусе, курсор в конце —
    /// тап поставил бы его в середину строки.
    @MainActor
    func replaceText(_ text: String) {
        let current = (value as? String) ?? ""
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 3))
        typeText(text)
    }
}
