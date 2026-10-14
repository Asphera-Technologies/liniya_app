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

        // Важность — в карточке цели, ниже прогресса и того, где цель сейчас.
        goalRow.tap()
        XCTAssertTrue(app.buttons["Высокая"].waitForExistence(timeout: 5), "В карточке цели есть «Важность»")
        scrollTo(app.buttons["Высокая"], in: app)
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

    // MARK: - 7. Одно действие: «Начать», «Другое», «Завершить»

    @MainActor
    func test7NowStartOtherFinish() throws {
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
        XCTAssertTrue(now.buttons["Не сейчас"].exists, "У предложения есть «Не сейчас»")
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
        minimizeFocus(app)
        XCTAssertTrue(now.buttons["Завершить"].waitForExistence(timeout: 10), "Начатое — «в работе» с «Завершить»")
        XCTAssertTrue(now.buttons["Не сейчас"].exists, "Начатое можно отложить")
        XCTAssertFalse(now.buttons["Другое"].exists, "У начатого «Другое» нет")
        XCTAssertTrue(now.buttons["Развернуть"].exists, "Свёрнутый фокус можно развернуть")
        XCTAssertTrue(now.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Начато в")).firstMatch.exists)
        scrollTo(now, in: app)
        snapshot(app, "26 В работе")

        now.buttons["Завершить"].tap()
        XCTAssertTrue(now.buttons["Начать"].waitForExistence(timeout: 10), "После «Завершить» — следующее действие")
        XCTAssertFalse(now.staticTexts["Проверить сборку"].exists)
        snapshot(app, "27 Следующее действие")
    }

    // MARK: - 12. Состояния задачи: «Начать», «Не сейчас», «Завершить» везде

    @MainActor
    func test12StartNotNowFinish() throws {
        let app = launch()
        addTask(app, "Ответить клиенту сегодня 15 минут, важно")
        addTask(app, "Проверить сборку сегодня 15 минут")
        addTask(app, "Разобрать письмо сегодня 10 минут")

        // «Сейчас»: три действия.
        openTab(app, "Сегодня", index: 0)
        let now = nowCard(app)
        XCTAssertTrue(now.waitForExistence(timeout: 15))
        XCTAssertTrue(now.staticTexts["Ответить клиенту"].waitForExistence(timeout: 5), "Важное — первым")
        for action in ["Начать", "Не сейчас", "Другое"] {
            XCTAssertTrue(now.buttons[action].exists, "У «Сейчас» есть «\(action)»")
        }
        scrollTo(now, in: app)
        snapshot(app, "50 Сейчас: Начать, Не сейчас, Другое")

        // «Не сейчас» — Linea предлагает другое, отложенное ждёт полтора часа.
        now.buttons["Не сейчас"].tap()
        XCTAssertTrue(now.staticTexts["Ответить клиенту"].waitForNonExistence(timeout: 10), "После «Не сейчас» — другое дело")
        XCTAssertTrue(now.buttons["Начать"].waitForExistence(timeout: 5))
        let started = now.staticTexts["Проверить сборку"].exists ? "Проверить сборку" : "Разобрать письмо"
        let other = started == "Проверить сборку" ? "Разобрать письмо" : "Проверить сборку"
        XCTAssertTrue(now.staticTexts[started].exists, "Предложено одно из оставшихся")
        scrollTo(now, in: app)
        snapshot(app, "51 Сейчас после «Не сейчас»")

        // «Начать» — в работе: «Завершить» и «Не сейчас», без «Другое».
        // Ответ и вопрос над «Сейчас» сдвигают кнопки вниз — под строку Linea AI.
        bringAboveCommandBar(now.buttons["Начать"], in: app)
        now.buttons["Начать"].tap()
        minimizeFocus(app)
        XCTAssertTrue(now.buttons["Завершить"].waitForExistence(timeout: 10), "Начатое — с «Завершить»")
        XCTAssertTrue(now.buttons["Не сейчас"].exists)
        XCTAssertFalse(now.buttons["Другое"].exists, "У начатого «Другое» нет")
        XCTAssertTrue(now.staticTexts[started].exists)
        scrollTo(now, in: app)
        snapshot(app, "52 Сейчас: в работе")

        // «План»: начатая и отложенная подписаны.
        openTab(app, "План", index: 1)
        let deferredRow = button(app, startingWith: "Ответить клиенту")
        XCTAssertTrue(deferredRow.waitForExistence(timeout: 5))
        XCTAssertTrue(deferredRow.label.contains("Не сейчас — до "), "Отложенная подписана: \(deferredRow.label)")
        let startedRow = button(app, startingWith: started)
        XCTAssertTrue(startedRow.label.contains("В работе с "), "Начатая подписана: \(startedRow.label)")
        snapshot(app, "53 План: в работе и не сейчас")

        // Карточка начатой: как идёт, «Завершить» — и сколько заняло на самом деле.
        bringAboveCommandBar(startedRow, in: app)
        startedRow.tap()
        XCTAssertTrue(app.navigationBars["Задача"].waitForExistence(timeout: 5))
        let status = app.staticTexts["task.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5), "В карточке видно, как идёт задача")
        XCTAssertTrue(status.label.hasPrefix("В работе с "), status.label)
        XCTAssertTrue(app.buttons["Не сейчас"].exists)
        snapshot(app, "54 Карточка: в работе")
        app.buttons["Завершить"].tap()
        let done = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "Сделано в [0-9]{1,2}:[0-9]{2} · за [0-9]+ мин"))
            .firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Сделано и сколько заняло: \(status.label)")
        XCTAssertFalse(app.buttons["Завершить"].exists, "Сделанную не завершают второй раз")
        XCTAssertFalse(app.buttons["Начать"].exists)
        snapshot(app, "55 Карточка: сделано и сколько заняло")
        app.navigationBars["Задача"].buttons["Отмена"].tap()
        XCTAssertTrue(app.navigationBars["Задача"].waitForNonExistence(timeout: 5))

        // Меню строки: «Начать», у начатой — «Завершить» и «Не сейчас».
        let otherRow = button(app, startingWith: other)
        XCTAssertTrue(otherRow.waitForExistence(timeout: 5))
        bringAboveCommandBar(otherRow, in: app)
        otherRow.press(forDuration: 1.2)
        tapMenuItem(app, "Начать")
        minimizeFocus(app)
        let startedOther = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", other, "В работе с "))
            .firstMatch
        XCTAssertTrue(startedOther.waitForExistence(timeout: 5), "«Начать» из меню")
        bringAboveCommandBar(startedOther, in: app)
        startedOther.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Завершить"].waitForExistence(timeout: 5), "У начатой в меню — «Завершить»")
        XCTAssertTrue(app.buttons["Не сейчас"].exists)
        XCTAssertFalse(app.buttons["Начать"].exists, "Начатую не начинают второй раз")
        snapshot(app, "56 Меню начатой задачи")
        tapMenuItem(app, "Не сейчас")
        let deferredOther = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", other, "Не сейчас — до "))
            .firstMatch
        XCTAssertTrue(deferredOther.waitForExistence(timeout: 5), "«Не сейчас» из меню")
        snapshot(app, "57 План после «Не сейчас» из меню")
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

    // MARK: - 9. Новая цель подробно: «Рассказать подробнее», понять, потом создать

    @MainActor
    func test9GoalIntake() throws {
        let app = launch()
        openTab(app, "План", index: 1)
        app.buttons["plan.addGoal"].tap()
        let line = field(app, "goal.line")
        XCTAssertTrue(line.waitForExistence(timeout: 5), "«+ Цель» открывает быструю цель")
        focus(line, in: app)
        line.typeText("Запустить закрытую beta Linea")
        app.buttons["goal.more"].tap()
        let title = field(app, "goal.title")
        XCTAssertTrue(title.waitForExistence(timeout: 5), "«Рассказать подробнее» открывает рассказ")
        XCTAssertEqual(title.value as? String, "Запустить закрытую beta Linea", "Строка стала названием")
        XCTAssertTrue(app.staticTexts["Что уже сделано, где ты сейчас и что будет означать, что цель достигнута?"].exists)
        XCTAssertTrue(app.buttons["goal.voice"].exists, "Можно рассказать голосом")
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
        XCTAssertEqual(app.staticTexts["goal.review.stage"].label, "Стадия — Разработка", "Прототип и переработка — разработка")
        XCTAssertTrue(element(app, labelContaining: "0 из 50 тестировщиков").exists, "Число цели — из рассказа")
        snapshot(app, "35 Я поняла цель так")

        app.buttons["goal.change"].tap()
        XCTAssertTrue(field(app, "goal.edit.title").waitForExistence(timeout: 5), "«Изменить» открывает правку")
        snapshot(app, "36 Изменить")
        app.buttons["goal.edit.done"].tap()
        XCTAssertTrue(app.buttons["goal.confirm"].waitForExistence(timeout: 5), "После правки — снова «Я поняла цель так»")
        app.buttons["goal.confirm"].tap()
        XCTAssertTrue(app.buttons["goal.confirm"].waitForNonExistence(timeout: 5), "«Всё верно» создаёт цель")
        XCTAssertTrue(button(app, startingWith: "Запустить закрытую beta Linea").waitForExistence(timeout: 5), "Цель в плане")

        // Подробно, но без рассказа — Linea задаёт один вопрос, потом следующий.
        app.buttons["plan.addGoal"].tap()
        let short = field(app, "goal.line")
        XCTAssertTrue(short.waitForExistence(timeout: 5))
        focus(short, in: app)
        short.typeText("Запустить продукт")
        app.buttons["goal.more"].tap()
        XCTAssertTrue(field(app, "goal.title").waitForExistence(timeout: 5))
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

        // Карточка цели хранит, как Linea её поняла: этапы и числа, стадия.
        button(app, startingWith: "Запустить закрытую beta Linea").tap()
        XCTAssertTrue(app.navigationBars["Цель"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Результат"].exists)
        XCTAssertEqual(app.buttons["goal.method"].label, "Как считать прогресс: Этапы и числа")
        XCTAssertEqual(app.buttons["goal.stage"].label, "Стадия: Разработка")
        snapshot(app, "39 Карточка цели: как Linea её поняла")
    }

    // MARK: - 13. Быстрая цель: пример заказчика

    @MainActor
    func test13QuickGoal() throws {
        let app = launch()
        openTab(app, "План", index: 1)
        app.buttons["plan.addGoal"].tap()
        let line = field(app, "goal.line")
        XCTAssertTrue(line.waitForExistence(timeout: 5), "«+ Цель» открывает быструю цель")
        XCTAssertFalse(app.buttons["goal.create"].isEnabled, "Без строки создавать нечего")
        XCTAssertFalse(app.staticTexts["Расскажи подробнее"].exists, "Не форма — один вопрос")
        snapshot(app, "40 Быстрая цель: один вопрос")

        focus(line, in: app)
        line.typeText("Выпустить Линия в TestFlight до 15-го октября")
        let understood = app.staticTexts["goal.understood.title"]
        XCTAssertTrue(understood.waitForExistence(timeout: 5), "Linea показывает, как поняла строку")
        XCTAssertEqual(understood.label, "Выпустить Линия в TestFlight")
        XCTAssertTrue(app.staticTexts["goal.understood.summary"].label.hasPrefix("до 15 октября"))
        XCTAssertTrue(chip(app, "Срок: до 15 окт").exists)
        XCTAssertTrue(chip(app, "Важность: Средняя").exists)
        XCTAssertTrue(chip(app, "Прогресс: Этапы").exists, "Тип цели — проект: прогресс этапами")
        XCTAssertTrue(chip(app, "Чья цель: От меня").exists, "Своя цель — без вопроса о своей части")
        XCTAssertFalse(field(app, "goal.part").exists)
        snapshot(app, "41 Быстрая цель: как Linea поняла")

        // Самое важное — чипами, как у задачи.
        chip(app, "Важность").tap()
        tapMenuItem(app, "Высокая")
        XCTAssertTrue(chip(app, "Важность: Высокая").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["goal.understood.summary"].label.hasSuffix("Высокая"))
        snapshot(app, "42 Быстрая цель: важность чипом")

        app.buttons["goal.create"].tap()
        XCTAssertTrue(line.waitForNonExistence(timeout: 5), "«Создать цель» создаёт цель и закрывает лист")
        let row = button(app, startingWith: "Выпустить Линия в TestFlight")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Цель в плане")
        XCTAssertTrue(row.label.contains("Этапы не заданы"), "Процента нет: этапов ещё нет")
        XCTAssertTrue(row.label.contains("до 15 окт"))
        snapshot(app, "43 Быстрая цель в плане")

        // В карточке — стадии запуска продукта и время пересмотра.
        row.tap()
        XCTAssertTrue(app.navigationBars["Цель"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["goal.stage"].label, "Стадия: не выбрана", "О том, где цель сейчас, не сказано")
        app.buttons["goal.stage"].tap()
        tapMenuItem(app, "Разработка")
        XCTAssertTrue(app.buttons["goal.stage"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["goal.stage"].label, "Стадия: Разработка")
        XCTAssertTrue(app.staticTexts["goal.card.caption"].label.contains("обновлена сегодня"))
        snapshot(app, "44 Карточка цели: стадия")
        saveGoalCard(app)
        XCTAssertTrue(app.navigationBars["Цель"].waitForNonExistence(timeout: 5))
    }

    // MARK: - 14. Прогресс цели: число, этапы, без процентов, отмечаю сам

    @MainActor
    func test14GoalProgress() throws {
        let app = launch()
        openTab(app, "План", index: 1)
        createQuickGoal(app, "Получить 50 пользователей")
        let row = button(app, startingWith: "Получить 50 пользователей")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("0 из 50 пользователей · 0%"), "Измеримая цель — число с целью: \(row.label)")

        // Изменение числа обновляет прогресс.
        row.tap()
        let current = field(app, "goal.metric.current")
        XCTAssertTrue(current.waitForExistence(timeout: 5), "У числа — «Сейчас»")
        focus(current, in: app)
        current.replaceText("18")
        let summary = app.staticTexts["goal.progress.summary"]
        XCTAssertTrue(waitForLabel(summary, "18 из 50 пользователей · 36%"), "Прогресс: \(summary.label)")
        snapshot(app, "45 Число: 18 из 50 — 36%")
        saveGoalCard(app)
        XCTAssertTrue(waitForLabel(row, containing: "18 из 50 пользователей · 36%"), "Строка цели: \(row.label)")
        snapshot(app, "46 План: 18 из 50 — 36%")

        // Этапы: закрытие этапа обновляет прогресс, без весов процента нет.
        row.tap()
        XCTAssertTrue(app.buttons["goal.method"].waitForExistence(timeout: 5))
        app.buttons["goal.method"].tap()
        tapMenuItem(app, "Этапы")
        XCTAssertTrue(waitForLabel(summary, "Этапы не заданы"))
        addMilestone(app, "Core loop")
        addMilestone(app, "Onboarding")
        let toggle = app.buttons.matching(identifier: "goal.milestone.toggle").firstMatch
        toggle.tap()
        XCTAssertTrue(waitForLabel(summary, "1 из 2 этапов"), "Без весов — «1 из 2 этапов», без процента: \(summary.label)")
        snapshot(app, "47 Этапы: закрыт один")
        saveGoalCard(app)
        XCTAssertTrue(waitForLabel(row, containing: "1 из 2 этапов"), "Строка цели: \(row.label)")
        XCTAssertFalse(row.label.contains("%"), "Процента нет")

        // Без процентов: стадия, последнее продвижение, действия за 30 дней.
        row.tap()
        XCTAssertTrue(app.buttons["goal.method"].waitForExistence(timeout: 5))
        app.buttons["goal.method"].tap()
        tapMenuItem(app, "Без процентов")
        let qualitative = app.descendants(matching: .any).matching(identifier: "goal.qualitative").firstMatch
        XCTAssertTrue(qualitative.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Последнее продвижение"].exists)
        XCTAssertTrue(app.staticTexts["сегодня"].exists, "Этап закрыт сегодня — это продвижение")
        snapshot(app, "48 Без процентов")
        saveGoalCard(app)
        XCTAssertTrue(waitForLabel(row, containing: "продвижение — сегодня"), "Строка цели: \(row.label)")
        XCTAssertFalse(row.label.contains("%"), "Без процентов — и в «Плане»")

        // Отмечаю сам: слова вместо процента.
        row.tap()
        XCTAssertTrue(app.buttons["goal.method"].waitForExistence(timeout: 5))
        app.buttons["goal.method"].tap()
        tapMenuItem(app, "Отмечаю сам")
        app.buttons["goal.manual.almostDone"].tap()
        XCTAssertTrue(waitForLabel(summary, "Почти готово"))
        snapshot(app, "49 Отмечаю сам")
        saveGoalCard(app)
        XCTAssertTrue(waitForLabel(row, containing: "Почти готово"), "Строка цели: \(row.label)")
        snapshot(app, "50 План: почти готово")
    }

    // MARK: - 15. Цель компании: общий прогресс и своя часть отдельно

    @MainActor
    func test15CompanyGoal() throws {
        let app = launch()
        openTab(app, "План", index: 1)
        app.buttons["plan.addGoal"].tap()
        let line = field(app, "goal.line")
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        focus(line, in: app)
        line.typeText("Довести выручку компании до 5 млн ₽ в месяц")
        XCTAssertTrue(chip(app, "Чья цель: От компании").waitForExistence(timeout: 5), "Компанию Linea видит в словах")
        let part = field(app, "goal.part")
        XCTAssertTrue(part.waitForExistence(timeout: 5), "У цели компании — «За какую часть отвечаешь ты?»")
        XCTAssertTrue(app.staticTexts["За какую часть отвечаешь ты?"].exists)
        XCTAssertTrue(app.buttons["goal.part.voice"].exists, "Свою часть можно рассказать голосом")
        focus(part, in: app)
        part.typeText("Новые enterprise-клиенты и ключевые переговоры")
        snapshot(app, "51 Цель компании: своя часть")
        app.buttons["goal.create"].tap()
        XCTAssertTrue(line.waitForNonExistence(timeout: 5))

        let row = button(app, startingWith: "Довести выручку компании")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Компания · 0 из 5 млн ₽ · 0%"), "Строка цели: \(row.label)")
        XCTAssertTrue(row.label.contains("Моя часть: действий пока нет"), "Строка цели: \(row.label)")

        // Общая цель — то, что человек знает о выручке компании; своя часть —
        // его число. Это два разных показателя.
        row.tap()
        XCTAssertTrue(app.navigationBars["Цель"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Эта цель зависит только от тебя или от команды?"].exists)
        XCTAssertTrue(app.staticTexts["Общая цель"].exists)
        XCTAssertTrue(app.staticTexts["Моя часть"].exists)
        XCTAssertEqual(field(app, "goal.part").value as? String, "Новые enterprise-клиенты и ключевые переговоры")
        let total = field(app, "goal.metric.current")
        focus(total, in: app)
        total.replaceText("3200000")
        let summary = app.staticTexts["goal.progress.summary"]
        XCTAssertTrue(waitForLabel(summary, "3,2 млн из 5 млн ₽ · 64%"), "Общая цель: \(summary.label)")
        let addOwn = app.buttons["goal.contribution.add"]
        scrollTo(addOwn, in: app)
        addOwn.tap()
        let ownUnit = field(app, "goal.contribution.unit")
        XCTAssertTrue(ownUnit.waitForExistence(timeout: 5))
        focus(ownUnit, in: app)
        ownUnit.typeText("enterprise-клиентов")
        let ownTarget = field(app, "goal.contribution.target")
        focus(ownTarget, in: app)
        ownTarget.replaceText("5")
        let ownCurrent = field(app, "goal.contribution.current")
        focus(ownCurrent, in: app)
        ownCurrent.replaceText("2")
        snapshot(app, "52 Общая цель и моя часть")
        saveGoalCard(app)
        XCTAssertTrue(waitForLabel(row, containing: "Компания · 3,2 млн из 5 млн ₽ · 64%"), "Строка цели: \(row.label)")
        XCTAssertTrue(row.label.contains("Моя часть: 2 из 5 enterprise-клиентов · 40%"), "Строка цели: \(row.label)")
        snapshot(app, "53 План: цель компании и моя часть")

        // «От меня», потом снова «От команды» — цель опять компании, а не
        // просто команды (баг тестировщика, раунд 7).
        row.tap()
        XCTAssertTrue(app.navigationBars["Цель"].waitForExistence(timeout: 5))
        app.buttons["От меня"].tap()
        XCTAssertTrue(app.buttons["Вся компания"].waitForNonExistence(timeout: 5), "У своей цели нет выбора команды или компании")
        saveGoalCard(app)
        XCTAssertTrue(waitForLabel(row, containing: "3,2 млн из 5 млн ₽"), "Строка цели: \(row.label)")
        XCTAssertFalse(row.label.contains("Компания"), "Своя цель: \(row.label)")
        row.tap()
        XCTAssertTrue(app.navigationBars["Цель"].waitForExistence(timeout: 5))
        app.buttons["От команды"].tap()
        let company = app.buttons.matching(NSPredicate(format: "label == %@ AND isSelected == true", "Вся компания")).firstMatch
        XCTAssertTrue(company.waitForExistence(timeout: 5), "Снова «Вся компания», а не «Команда»")
        saveGoalCard(app)
        XCTAssertTrue(waitForLabel(row, containing: "Компания · 3,2 млн из 5 млн ₽ · 64%"), "Строка цели: \(row.label)")
        snapshot(app, "53а План: снова цель компании")
    }

    // MARK: - 16. Баланс дня: окно для важной цели среди текущих дел

    @MainActor
    func test16DayBalance() throws {
        let app = launch()
        openTab(app, "План", index: 1)
        app.buttons["plan.addGoal"].tap()
        let line = field(app, "goal.line")
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        focus(line, in: app)
        line.typeText("Запустить Линия Beta")
        chip(app, "Важность").tap()
        tapMenuItem(app, "Высокая")
        XCTAssertTrue(chip(app, "Важность: Высокая").waitForExistence(timeout: 5))
        app.buttons["goal.create"].tap()
        XCTAssertTrue(line.waitForNonExistence(timeout: 5))

        // Пример заказчика: обязательства и быт, ни одного шага к цели.
        addTask(app, "Отправить договор клиенту сегодня 15 минут")
        addTask(app, "Оплатить интернет сегодня 15 минут")
        addTask(app, "Купить продукты сегодня 15 минут")
        addTask(app, "Разобрать почту сегодня 15 минут")

        openTab(app, "Сегодня", index: 0)
        let offer = app.descendants(matching: .any).matching(identifier: "today.goalOffer").firstMatch
        XCTAssertTrue(offer.waitForExistence(timeout: 15), "Linea замечает состав дня")
        scrollTo(offer, in: app)
        XCTAssertTrue(offer.staticTexts["Сегодня много текущих дел."].exists)
        XCTAssertTrue(offer.staticTexts["Хочешь оставить небольшое окно для цели «Запустить Линия Beta»?"].exists)
        XCTAssertEqual(app.staticTexts["today.goalOffer.detail"].label,
                       "1 обязательство · 2 бытовых дела · 1 другое дело · 0 шагов к целям")
        XCTAssertTrue(offer.buttons["Не сегодня"].exists)
        snapshot(app, "54 Баланс дня: окно для цели")

        offer.buttons["Оставить 30 минут"].tap()
        let done = app.descendants(matching: .any).matching(identifier: "today.goalOffer.done").firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Linea подтверждает окно")
        XCTAssertTrue(done.label.hasPrefix("Оставила 30 минут для цели «Запустить Линия Beta»"), "Подтверждение: \(done.label)")
        snapshot(app, "55 Окно оставлено")

        openTab(app, "План", index: 1)
        let window = button(app, startingWith: "Окно для цели «Запустить Линия Beta»")
        XCTAssertTrue(window.waitForExistence(timeout: 5), "Окно — задача к цели на сегодня")
        snapshot(app, "56 План: окно для цели")

        // Ответили — в этот день больше не спрашиваем.
        openTab(app, "Сегодня", index: 0)
        XCTAssertTrue(nowCard(app).waitForExistence(timeout: 10))
        XCTAssertFalse(offer.exists, "После ответа вопрос не повторяется")
    }

    // MARK: - 17. Фокус после «Начать»: название, сколько, с какого времени, «Завершить»

    @MainActor
    func test17FocusAfterStart() throws {
        let app = launch()
        addTask(app, "Подготовить презентацию сегодня 45 минут, важно")

        // «Сейчас» → «Начать» — открывается фокус, а не помодоро.
        openTab(app, "Сегодня", index: 0)
        let now = nowCard(app)
        XCTAssertTrue(now.waitForExistence(timeout: 15))
        XCTAssertTrue(now.staticTexts["Подготовить презентацию"].waitForExistence(timeout: 5))
        now.buttons["Начать"].tap()
        let focusTitle = app.staticTexts["focus.title"]
        XCTAssertTrue(focusTitle.waitForExistence(timeout: 10), "После «Начать» — фокус")
        XCTAssertEqual(focusTitle.label, "Подготовить презентацию")
        XCTAssertTrue(app.staticTexts["~45 мин"].exists, "Сколько отведено")
        XCTAssertTrue(app.staticTexts["focus.started"].label.hasPrefix("Начато в "), app.staticTexts["focus.started"].label)
        XCTAssertTrue(app.buttons["focus.finish"].exists)
        XCTAssertTrue(app.buttons["Не получается продолжить"].exists)
        XCTAssertTrue(app.staticTexts["Можно выйти из приложения — выполнение продолжается."].exists)
        snapshot(app, "60 Фокус после «Начать»")

        // Вышел из приложения и вернулся — дело всё ещё в работе.
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(focusTitle.waitForExistence(timeout: 10), "После возврата фокус на месте")
        snapshot(app, "61 Фокус после возврата в приложение")

        // «Свернуть» — на «Сегодня» дело «в работе», «Развернуть» возвращает фокус.
        minimizeFocus(app)
        XCTAssertTrue(now.buttons["Развернуть"].waitForExistence(timeout: 5), "Свёрнутый фокус можно развернуть")
        scrollTo(now, in: app)
        snapshot(app, "62 Фокус свёрнут")
        now.buttons["Развернуть"].tap()
        XCTAssertTrue(focusTitle.waitForExistence(timeout: 5), "Фокус снова открыт")

        // «Завершить» — фокус закрылся, над «Сейчас» — сколько заняло.
        app.buttons["focus.finish"].tap()
        XCTAssertTrue(focusTitle.waitForNonExistence(timeout: 10), "После «Завершить» фокус закрыт")
        let note = app.descendants(matching: .any).matching(identifier: "now.note").firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10), "Linea отвечает на «Завершить»")
        XCTAssertTrue(note.label.hasPrefix("Сделано за "), "Ответ: \(note.label)")
        snapshot(app, "63 Сделано: сколько заняло")

        // «Начать» в карточке задачи — фокус под карточкой, виден, когда её закрыли.
        addTask(app, "Ответить клиенту сегодня 15 минут")
        openTab(app, "План", index: 1)
        let row = button(app, startingWith: "Ответить клиенту")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        bringAboveCommandBar(row, in: app)
        row.tap()
        XCTAssertTrue(app.navigationBars["Задача"].waitForExistence(timeout: 5))
        app.buttons["Начать"].tap()
        XCTAssertTrue(app.staticTexts["task.status"].waitForExistence(timeout: 5), "В карточке — «В работе с …»")
        app.navigationBars["Задача"].buttons["Отмена"].tap()
        XCTAssertTrue(focusTitle.waitForExistence(timeout: 10), "Карточку закрыли — фокус на экране")
        XCTAssertEqual(focusTitle.label, "Ответить клиенту")
        XCTAssertTrue(app.staticTexts["~15 мин"].exists)

        // «Не получается продолжить» — Linea отпускает дело и подбирает другое.
        app.buttons["Не получается продолжить"].tap()
        XCTAssertTrue(focusTitle.waitForNonExistence(timeout: 10), "Фокус закрыт")
        let released = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@",
                                                        "Ответить клиенту", "Не сейчас — до ")).firstMatch
        XCTAssertTrue(released.waitForExistence(timeout: 5), "Отпущенное дело — «Не сейчас»")
        snapshot(app, "64 План после «Не получается продолжить»")
        openTab(app, "Сегодня", index: 0)
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        XCTAssertEqual(note.label, "Хорошо, подберу другое.")
        snapshot(app, "65 Сегодня: «Хорошо, подберу другое.»")
    }

    // MARK: - 18. «Не сейчас»: «Хорошо, подберу другое.», иногда «Почему не сейчас?»

    @MainActor
    func test18NotNowWhy() throws {
        var app = launch()
        addTask(app, "Подготовить презентацию сегодня 45 минут, важно")
        addTask(app, "Разобрать письмо сегодня 15 минут")
        addTask(app, "Оплатить интернет сегодня 10 минут")

        openTab(app, "Сегодня", index: 0)
        var now = nowCard(app)
        XCTAssertTrue(now.waitForExistence(timeout: 15))
        XCTAssertTrue(now.staticTexts["Подготовить презентацию"].waitForExistence(timeout: 5))
        now.buttons["Не сейчас"].tap()
        var note = app.descendants(matching: .any).matching(identifier: "now.note").firstMatch
        XCTAssertTrue(waitForLabel(note, "Хорошо, подберу другое.", timeout: 10), "Тон без упрёка: \(note.label)")
        var question = app.descendants(matching: .any).matching(identifier: "now.question").firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 5), "Отложили важное — Linea спрашивает почему")
        XCTAssertTrue(question.staticTexts["Почему не сейчас?"].exists)
        for reason in ["Нет времени", "Нет сил", "Не хочется", "Неактуально"] {
            XCTAssertTrue(question.buttons[reason].exists, "Ответ «\(reason)»")
        }
        XCTAssertTrue(now.staticTexts["Подготовить презентацию"].waitForNonExistence(timeout: 5), "Предложение убрано")
        XCTAssertTrue(now.buttons["Начать"].exists, "Linea предложила другое")
        scrollTo(question, in: app)
        snapshot(app, "66 Не сейчас: почему?")

        // «Нет времени» — Linea вернётся к задаче, когда та поместится целиком.
        bringAboveCommandBar(question.buttons["Нет времени"], in: app)
        question.buttons["Нет времени"].tap()
        XCTAssertTrue(question.waitForNonExistence(timeout: 5), "Ответили — вопроса нет")
        XCTAssertTrue(waitForLabel(note, containing: "Хорошо, вернусь к ней в "), "Ответ: \(note.label)")
        snapshot(app, "67 Нет времени: вернусь, когда поместится")

        // Обычное дело — без вопроса.
        bringAboveCommandBar(now.buttons["Не сейчас"], in: app)
        now.buttons["Не сейчас"].tap()
        XCTAssertTrue(waitForLabel(note, "Хорошо, подберу другое."), note.label)
        XCTAssertFalse(question.exists, "Про обычное дело Linea не спрашивает")
        snapshot(app, "68 Не сейчас без вопроса")

        // «Неактуально» — из планов; «Вернуть» возвращает.
        app.terminate()
        app = launch()
        addTask(app, "Подготовить презентацию сегодня 45 минут, важно")
        addTask(app, "Оплатить интернет сегодня 10 минут")
        openTab(app, "Сегодня", index: 0)
        now = nowCard(app)
        note = app.descendants(matching: .any).matching(identifier: "now.note").firstMatch
        question = app.descendants(matching: .any).matching(identifier: "now.question").firstMatch
        XCTAssertTrue(now.staticTexts["Подготовить презентацию"].waitForExistence(timeout: 15))
        now.buttons["Не сейчас"].tap()
        XCTAssertTrue(question.waitForExistence(timeout: 10))
        bringAboveCommandBar(question.buttons["Неактуально"], in: app)
        question.buttons["Неактуально"].tap()
        XCTAssertTrue(waitForLabel(note, "Убрала из планов."), note.label)
        let restore = app.buttons["now.restore"]
        XCTAssertTrue(restore.exists, "Рядом — «Вернуть»")
        snapshot(app, "69 Неактуально: убрала из планов")
        restore.tap()
        XCTAssertTrue(waitForLabel(note, "Вернула в планы."), note.label)
        openTab(app, "План", index: 1)
        XCTAssertTrue(button(app, startingWith: "Подготовить презентацию").waitForExistence(timeout: 5), "Задача снова в планах")

        // «Нет сил» — Linea пока предлагает полегче.
        app.terminate()
        app = launch()
        addTask(app, "Подготовить презентацию сегодня 45 минут, важно")
        addTask(app, "Оплатить интернет сегодня 10 минут")
        openTab(app, "Сегодня", index: 0)
        now = nowCard(app)
        note = app.descendants(matching: .any).matching(identifier: "now.note").firstMatch
        question = app.descendants(matching: .any).matching(identifier: "now.question").firstMatch
        XCTAssertTrue(now.staticTexts["Подготовить презентацию"].waitForExistence(timeout: 15))
        now.buttons["Не сейчас"].tap()
        XCTAssertTrue(question.waitForExistence(timeout: 10))
        bringAboveCommandBar(question.buttons["Нет сил"], in: app)
        question.buttons["Нет сил"].tap()
        XCTAssertTrue(waitForLabel(note, "Хорошо, пока предложу что-то полегче."), note.label)
        XCTAssertTrue(now.staticTexts["Оплатить интернет"].waitForExistence(timeout: 5))
        XCTAssertTrue(now.staticTexts["Это полегче — пока сил немного."].waitForExistence(timeout: 5), "Причина — полегче")
        scrollTo(now, in: app)
        snapshot(app, "70 Нет сил: полегче")
    }

    // MARK: - 19. Перенести: позже сегодня, завтра, на неделе, «Пусть Linea решит»

    @MainActor
    func test19RescheduleLetLineaDecide() throws {
        let app = launch()
        addTask(app, "Подготовить презентацию сегодня 45 минут")
        addTask(app, "Ответить на письма сегодня 30 минут")
        openTab(app, "План", index: 1)

        // Свайп влево — меню заказчика.
        let presentation = button(app, startingWith: "Подготовить презентацию")
        XCTAssertTrue(presentation.waitForExistence(timeout: 5))
        bringAboveCommandBar(presentation, in: app)
        presentation.swipeLeft()
        XCTAssertTrue(app.staticTexts["Перенести «Подготовить презентацию»"].waitForExistence(timeout: 5))
        for option in ["Позже сегодня", "Завтра", "Пусть Linea решит", "Выбрать дату…"] {
            XCTAssertTrue(app.buttons[option].exists, "В «Перенести» есть «\(option)»")
        }
        XCTAssertTrue(button(app, startingWith: "На неделе · до ").exists, "В «Перенести» есть «На неделе»")
        XCTAssertFalse(app.buttons["Без даты"].exists, "Меню — как в постановке")
        snapshot(app, "71 Перенести: меню заказчика")

        // «Пусть Linea решит» — Linea сама находит окно и говорит, куда поставила.
        app.buttons["Пусть Linea решит"].tap()
        let toast = notice(app)
        XCTAssertTrue(toast.waitForExistence(timeout: 5), "Linea говорит, куда поставила")
        XCTAssertTrue(toast.label.hasPrefix("Поставила на "), "Сообщение: \(toast.label)")
        let decidedClock = Self.clock(in: toast.label)
        snapshot(app, "72 Пусть Linea решит: поставила")
        let decided = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@",
                                                       "Подготовить презентацию", "Время выбрала Linea")).firstMatch
        XCTAssertTrue(decided.waitForExistence(timeout: 5), "Под задачей — что время выбрала Linea")
        XCTAssertTrue(toast.waitForNonExistence(timeout: 6), "Сообщение уходит само")
        snapshot(app, "73 План: время выбрала Linea")

        // Меню долгого нажатия: «Перенести» → «Позже сегодня».
        let letters = button(app, startingWith: "Ответить на письма")
        bringAboveCommandBar(letters, in: app)
        letters.press(forDuration: 1.2)
        tapMenuItem(app, "Перенести")
        XCTAssertTrue(app.staticTexts["Перенести «Ответить на письма»"].waitForExistence(timeout: 5), "«Перенести» из меню")
        app.buttons["Позже сегодня"].tap()
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertTrue(toast.label.hasPrefix("Перенесла на "), "Сообщение: \(toast.label)")
        // Окно, которое Linea уже нашла презентации, занято — письма не
        // встают внахлёст (баг тестировщика, раунд 7).
        XCTAssertNotNil(decidedClock)
        XCTAssertNotEqual(Self.clock(in: toast.label), decidedClock, "Сообщения: \(decidedClock ?? "-") и \(toast.label)")
        let later = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@",
                                                     "Ответить на письма", "Позже — с ")).firstMatch
        XCTAssertTrue(later.waitForExistence(timeout: 5), "Под задачей — с какого времени")
        snapshot(app, "74 Позже сегодня")

        // Карточка: место выбирает Linea.
        bringAboveCommandBar(decided, in: app)
        decided.tap()
        XCTAssertTrue(app.navigationBars["Задача"].waitForExistence(timeout: 5))
        let status = app.staticTexts["task.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.hasPrefix("Время выбрала Linea: "), status.label)
        snapshot(app, "75 Карточка: время выбрала Linea")
        app.navigationBars["Задача"].buttons["Отмена"].tap()
    }

    // MARK: - 20. Мягкий обзор прогресса: «На этой неделе»

    @MainActor
    func test20WeeklyReview() throws {
        let app = launch()
        openTab(app, "План", index: 1)
        createQuickGoal(app, "Запустить Линия Beta")
        createQuickGoal(app, "Увеличить продажи Asphera")
        let titles = ["Отправить договор клиенту", "Подготовить отчёт для клиента", "Подготовить релиз", "Проверить сборку"]
        addTask(app, "Отправить договор клиенту сегодня 60 минут")
        addTask(app, "Подготовить отчёт для клиента сегодня 60 минут")
        addTask(app, "Подготовить релиз сегодня 30 минут для цели Beta")
        addTask(app, "Проверить сборку сегодня 15 минут для цели Beta")

        // Неделя: две задачи к цели и две — текущие обязательства, все закрыты.
        openTab(app, "План", index: 1)
        let closed = app.buttons.matching(NSPredicate(format: "label == %@", "Отметить невыполненной"))
        for (index, title) in titles.enumerated() {
            let row = button(app, startingWith: title)
            XCTAssertTrue(row.waitForExistence(timeout: 5), "Задача «\(title)»")
            bringAboveCommandBar(row, in: app)
            row.swipeRight()
            let deadline = Date().addingTimeInterval(5)
            while closed.count < index + 1, Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
            XCTAssertEqual(closed.count, index + 1, "«\(title)» закрыта")
        }

        let week = app.descendants(matching: .any).matching(identifier: "plan.week").firstMatch
        XCTAssertTrue(week.waitForExistence(timeout: 10), "В «Плане» — обзор недели")
        XCTAssertTrue(week.staticTexts["На этой неделе"].exists)
        let lines = app.descendants(matching: .any).matching(identifier: "plan.week.goal")
        XCTAssertTrue(lines.element(boundBy: 0).label.contains("Запустить Линия Beta"), lines.element(boundBy: 0).label)
        XCTAssertTrue(lines.element(boundBy: 0).label.contains("2 продвижения"), lines.element(boundBy: 0).label)
        XCTAssertTrue(lines.element(boundBy: 1).label.contains("Увеличить продажи Asphera"), lines.element(boundBy: 1).label)
        XCTAssertTrue(lines.element(boundBy: 1).label.contains("пока без продвижений"), lines.element(boundBy: 1).label)
        let observation = app.staticTexts["plan.week.observation"]
        XCTAssertEqual(observation.label,
                       "Большая часть недели ушла на текущие обязательства. По «Запустить Линия Beta» получилось продвинуться дважды.")
        scrollTo(observation, in: app)
        snapshot(app, "76 На этой неделе")

        // Прошлая неделя: целей тогда ещё не было — и обзора нет.
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Предыдущ")).firstMatch.tap()
        XCTAssertTrue(week.waitForNonExistence(timeout: 5), "Цели созданы на этой неделе — в обзоре прошлой их нет")
        snapshot(app, "77 Прошлая неделя без обзора")
    }

    // MARK: - 21. Защищённое окно под цель: разрешил — Linea оставляет время в плане

    @MainActor
    func test21ProtectedGoalWindow() throws {
        let app = launch()
        openTab(app, "План", index: 1)
        createQuickGoal(app, "Запустить Linea Beta")
        let goalRow = button(app, startingWith: "Запустить Linea Beta")
        XCTAssertTrue(goalRow.waitForExistence(timeout: 5))
        goalRow.tap()
        XCTAssertTrue(app.navigationBars["Цель"].waitForExistence(timeout: 5))
        let toggle = app.switches["goal.window.toggle"]
        scrollTo(toggle, in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "В карточке цели — «Защищённое окно»")
        snapshot(app, "78 Карточка цели: защищённое окно выключено")
        // Переключатель — справа в строке; тап по подписи его не трогает.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        let any = app.buttons["goal.window.part.any"]
        XCTAssertTrue(any.waitForExistence(timeout: 5), "Включил — видно, сколько и когда")
        any.tap()
        let summary = app.staticTexts["goal.window.summary"]
        XCTAssertTrue(waitForLabel(summary, "Каждый день · 30 мин · когда свободно"), summary.label)
        snapshot(app, "79 Защищённое окно: 30 мин, когда свободно")
        saveGoalCard(app)

        // «Дальше»: окно в плане — не задача и не событие календаря.
        openTab(app, "Сегодня", index: 0)
        let block = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                                                     "Продвинуть «Запустить Linea Beta»", "защищённое окно")).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 15), "Окно в плане дня")
        scrollTo(block, in: app)
        snapshot(app, "80 Дальше: защищённое окно")

        // «Сейчас» — само окно; «Начать» берёт его в работу.
        let now = nowCard(app)
        XCTAssertTrue(now.staticTexts["Продвинуть «Запустить Linea Beta»"].waitForExistence(timeout: 10), "Сейчас — окно цели")
        let reason = now.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@",
                                                          "Сейчас время для цели «Запустить Linea Beta» — до ")).firstMatch
        XCTAssertTrue(reason.exists, "Причина — время для цели")
        scrollTo(now, in: app)
        snapshot(app, "81 Сейчас: время для цели")
        bringAboveCommandBar(now.buttons["Начать"], in: app)
        now.buttons["Начать"].tap()
        let focusTitle = app.staticTexts["focus.title"]
        XCTAssertTrue(focusTitle.waitForExistence(timeout: 10), "Окно в работе — фокус")
        XCTAssertEqual(focusTitle.label, "Продвинуть «Запустить Linea Beta»")
        snapshot(app, "82 Фокус: окно цели")
        minimizeFocus(app)
        openTab(app, "План", index: 1)
        XCTAssertTrue(button(app, startingWith: "Продвинуть «Запустить Linea Beta»").waitForExistence(timeout: 5),
                      "Начатое окно — задача к цели")
    }

    // MARK: - 22. Обновить состояние цели: что изменилось — Linea показывает, потом меняет

    @MainActor
    func test22GoalStateUpdate() throws {
        let app = launch()
        openTab(app, "План", index: 1)
        createQuickGoal(app, "Запустить Linea Beta")
        let row = button(app, startingWith: "Запустить Linea Beta")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.navigationBars["Цель"].waitForExistence(timeout: 5))
        let update = app.buttons["goal.update"]
        scrollTo(update, in: app)
        update.tap()

        let text = field(app, "goal.update.text")
        XCTAssertTrue(text.waitForExistence(timeout: 5), "«Что изменилось?»")
        XCTAssertTrue(app.staticTexts["Что изменилось?"].exists)
        XCTAssertTrue(app.buttons["goal.update.voice"].exists, "Можно рассказать голосом")
        focus(text, in: app)
        text.typeText("TestFlight уже сделали, onboarding почти готов, но аналитику пока не подключали.")
        snapshot(app, "83 Что изменилось")
        app.buttons["goal.update.read"].tap()

        // Сначала — как Linea поняла; цель ещё не меняется.
        let items = app.staticTexts.matching(identifier: "goal.update.item")
        XCTAssertTrue(items.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(items.allElementsBoundByIndex.map(\.label), [
            "✓ TestFlight — завершено", "● Onboarding — почти готов", "○ Аналитика — не начата",
        ])
        XCTAssertEqual(app.staticTexts["goal.update.focus"].label,
                       "Новый фокус: закончить onboarding и подключить аналитику.")
        snapshot(app, "84 Обновлю состояние")

        // «Изменить» — снова к словам, сказанное на месте.
        app.buttons["goal.update.edit"].tap()
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        app.buttons["goal.update.read"].tap()
        XCTAssertTrue(items.firstMatch.waitForExistence(timeout: 5))
        app.buttons["goal.update.confirm"].tap()
        XCTAssertTrue(app.buttons["goal.update.confirm"].waitForNonExistence(timeout: 15), "Подтвердил — лист закрылся")

        // Карточка — уже обновлённая: этапы, «почти готов», новый фокус.
        let focusLine = app.staticTexts["goal.focus"]
        XCTAssertTrue(focusLine.waitForExistence(timeout: 5))
        XCTAssertEqual(focusLine.label, "Новый фокус: закончить onboarding и подключить аналитику.")
        XCTAssertTrue(app.staticTexts["goal.milestone.state"].exists, "У Onboarding — «почти готов»")
        snapshot(app, "85 Карточка после обновления")
        saveGoalCard(app)
        XCTAssertTrue(waitForLabel(row, containing: "1 из 3 этапов"), "Строка цели: \(row.label)")
        snapshot(app, "86 План: 1 из 3 этапов")
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

        // Влево — «Перенести»: короткий выбор; «Завтра» — и Linea говорит, куда.
        let mom = button(app, startingWith: "Позвонить маме")
        bringAboveCommandBar(mom, in: app)
        mom.swipeLeft()
        XCTAssertTrue(app.staticTexts["Перенести «Позвонить маме»"].waitForExistence(timeout: 5), "Свайп влево — «Перенести»")
        for option in ["Позже сегодня", "Завтра", "Пусть Linea решит", "Выбрать дату…"] {
            XCTAssertTrue(app.buttons[option].exists, "В «Перенести» есть «\(option)»")
        }
        snapshot(app, "41 Свайп влево — Перенести")
        app.buttons["Завтра"].tap()
        let moved = notice(app)
        XCTAssertTrue(moved.waitForExistence(timeout: 5), "Linea говорит, куда перенесла")
        XCTAssertEqual(moved.label, "Перенесла на завтра.")

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

        // Не уверена — пусто: два дня на выбор, время без дня и «вечером» не становятся датой.
        field.replaceText("Позвонить маме завтра в 10 или послезавтра вечером")
        XCTAssertTrue(chip(app, "Когда: Без даты").waitForExistence(timeout: 5), "Два дня на выбор — ни дня, ни времени")
        XCTAssertFalse(app.staticTexts["quickAdd.understood.title"].exists, "Понимать нечего — подсказки нет")
        snapshot(app, "47 Не уверена — пусто")

        // Одно «завтра» — день понятен, но название то же: «как поняла» не нужна.
        field.replaceText("Завтра")
        XCTAssertTrue(chip(app, "Когда: Завтра").waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["quickAdd.understood.title"].exists, "Название не изменилось — подсказки нет")

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
        // Длительность не названа — её оценивает Linea по словам (ADR-045).
        field.typeText("Ответить клиенту")
        XCTAssertTrue(chip(app, "Сколько займёт: ~10 мин").waitForExistence(timeout: 5), "Ответить — 10 минут")
        snapshot(app, "22 Ответить клиенту — ~10 мин")
        // «Сегодня» — чтобы в «Плане» под задачей было видно, что у неё задано.
        field.replaceText("Подготовить презентацию сегодня")
        XCTAssertTrue(chip(app, "Сколько займёт: ~1 ч").waitForExistence(timeout: 5), "Презентация — час")
        snapshot(app, "23 Подготовить презентацию — ~1 ч")
        app.buttons["Добавить задачу"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))

        // Карточка: оценка Linea подписью, свой выбор — одним тапом.
        openTab(app, "План", index: 1)
        let row = button(app, startingWith: "Подготовить презентацию")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        bringAboveCommandBar(row, in: app)
        row.tap()
        XCTAssertTrue(app.navigationBars["Задача"].waitForExistence(timeout: 5))
        let estimate = app.staticTexts["task.duration.estimate"]
        scrollTo(estimate, in: app)
        XCTAssertEqual(estimate.label, "~1 ч — оценка Linea")
        snapshot(app, "23а Карточка: оценка Linea")
        app.buttons["30 минут"].tap()
        XCTAssertTrue(estimate.waitForNonExistence(timeout: 5), "Выбрал сам — подписи Linea нет")
        app.navigationBars["Задача"].buttons["Готово"].tap()
        XCTAssertTrue(app.navigationBars["Задача"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(waitForLabel(row, containing: "~30 мин"), "Строка: \(row.label)")
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

    /// «13:24» из «Поставила на сегодня, 13:24.»
    static func clock(in text: String) -> String? {
        text.range(of: "[0-9]{1,2}:[0-9]{2}", options: .regularExpression).map { String(text[$0]) }
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
        focus(field, in: app)
        field.typeText(text)
        let add = app.buttons["Добавить задачу"]
        XCTAssertTrue(add.isEnabled)
        add.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "«\(text)» не добавилась")
    }

    /// Тап по полю, пока не появится клавиатура. Лист сам ставит фокус при
    /// появлении, и на подтормаживающем симуляторе поле получало его и тут же
    /// теряло — набор без клавиатуры падает.
    @MainActor
    private func focus(_ field: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<3 {
            field.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 5) { return }
        }
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
    /// жест по строке под ними попал бы в них. И строка стоит на месте: после
    /// «Готово» список переставляет задачи с анимацией, а жест по едущей
    /// строке не срабатывает.
    @MainActor
    private func bringAboveCommandBar(_ element: XCUIElement, in app: XCUIApplication) {
        let bar = app.buttons["Новая задача"].firstMatch
        var attempts = 0
        while element.exists, bar.exists, element.frame.maxY > bar.frame.minY - 12, attempts < 4 {
            app.swipeUp()
            attempts += 1
        }
        waitUntilStill(element)
    }

    /// Ждать, пока рамка элемента не перестанет меняться (до трёх секунд).
    @MainActor
    private func waitUntilStill(_ element: XCUIElement, timeout: TimeInterval = 3) {
        guard element.exists else { return }
        var last = element.frame
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.3)
            let current = element.frame
            if current == last { return }
            last = current
        }
    }

    /// «Готово» в карточке цели. Карточка закрывается, когда цель сохранена и
    /// день пересчитан, — на симуляторе без Apple Health это бывает и десять
    /// секунд: ждём, пока закроется, а не проверяем строку цели под ней.
    @MainActor
    private func saveGoalCard(_ app: XCUIApplication) {
        let card = app.navigationBars["Цель"]
        card.buttons["Готово"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 20), "Карточка цели закрылась")
    }

    /// После «Начать» открывается фокус — свернуть его, чтобы продолжить на
    /// экране под ним.
    @MainActor
    private func minimizeFocus(_ app: XCUIApplication) {
        let minimize = app.buttons["focus.minimize"]
        XCTAssertTrue(minimize.waitForExistence(timeout: 10), "После «Начать» открылся фокус")
        minimize.tap()
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 5), "Фокус свернулся")
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

    /// «+ Цель» → строка → «Создать цель».
    @MainActor
    private func createQuickGoal(_ app: XCUIApplication, _ text: String) {
        app.buttons["plan.addGoal"].tap()
        let line = field(app, "goal.line")
        XCTAssertTrue(line.waitForExistence(timeout: 5), "Быстрая цель не открылась")
        focus(line, in: app)
        line.typeText(text)
        app.buttons["goal.create"].tap()
        XCTAssertTrue(line.waitForNonExistence(timeout: 5), "Цель «\(text)» не создалась")
    }

    /// «+ Этап» в карточке цели и его название.
    @MainActor
    private func addMilestone(_ app: XCUIApplication, _ title: String) {
        let add = app.buttons["goal.milestone.add"]
        scrollTo(add, in: app)
        add.tap()
        let fields = app.descendants(matching: .any).matching(identifier: "goal.milestone.title")
            .matching(NSPredicate(format: "elementType == %d OR elementType == %d",
                                  XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue))
        let field = fields.element(boundBy: max(fields.count - 1, 0))
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Новый этап не появился")
        focus(field, in: app)
        field.typeText(title)
    }

    /// Подпись стала такой (или содержит текст) за несколько секунд.
    @MainActor
    private func waitForLabel(_ element: XCUIElement, _ label: String? = nil, containing text: String? = nil,
                              timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists {
                if let label, element.label == label { return true }
                if let text, element.label.contains(text) { return true }
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    /// «+ Цель» → строка → «Рассказать подробнее» → рассказ → «Я поняла цель
    /// так» → «Всё верно».
    @MainActor
    private func createGoal(_ app: XCUIApplication, _ title: String, details: String) {
        app.buttons["plan.addGoal"].tap()
        let line = field(app, "goal.line")
        XCTAssertTrue(line.waitForExistence(timeout: 5), "«Новая цель» не открылась")
        focus(line, in: app)
        line.typeText(title)
        app.buttons["goal.more"].tap()
        XCTAssertTrue(field(app, "goal.title").waitForExistence(timeout: 5), "«Рассказать подробнее» не открылось")
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

    /// Сообщение сверху — куда Linea перенесла задачу.
    @MainActor
    private func notice(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "notice").firstMatch
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
