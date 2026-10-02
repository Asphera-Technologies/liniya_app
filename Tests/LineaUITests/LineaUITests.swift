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
        XCTAssertTrue(chip(app, "Когда: Сегодня").exists, "Чип дня по умолчанию — «Сегодня»")
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
        let today = calendar.buttons.matching(NSPredicate(format: "label CONTAINS %@", Self.dayMonth(daysFromNow: 0))).firstMatch
        if today.exists {
            today.tap()
            XCTAssertTrue(chip(app, "Когда: Сегодня").waitForExistence(timeout: 5), "Тап по дню выбирает его и закрывает календарь")
        } else {
            XCTFail("В календаре не нашёлся сегодняшний день")
            dismissPopover(app)
        }

        chip(app, "Когда:").tap()
        app.buttons["На неделе"].tap()
        XCTAssertTrue(chip(app, "Когда: На неделе").waitForExistence(timeout: 5))

        chip(app, "Когда:").tap()
        app.buttons["Срок…"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5), "«Срок…» открывает дату и время")
        snapshot(app, "08 Срок — дата и время")
        app.buttons["quickAdd.deadline.done"].tap()
        XCTAssertTrue(chip(app, "Когда: до").waitForExistence(timeout: 5), "Названный срок виден в чипе")

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
        openTab(app, "План", index: 1)
        XCTAssertTrue(button(app, startingWith: "Отчёт").waitForExistence(timeout: 5))
        snapshot(app, "12 План: задача без дня со сроком")
    }

    // MARK: - 3. Цель: важность, подсказка, явная связь

    @MainActor
    func test3GoalImportanceAndLinking() throws {
        let app = launch()
        openTab(app, "План", index: 1)
        app.buttons["plan.addGoal"].tap()
        let goalTitle = titleField(app)
        XCTAssertTrue(goalTitle.waitForExistence(timeout: 5))
        goalTitle.tap()
        goalTitle.typeText("Запустить MVP Linea")
        XCTAssertTrue(app.buttons["Высокая"].exists, "В редакторе цели есть «Важность»")
        app.buttons["Высокая"].tap()
        snapshot(app, "13 Новая цель с важностью")
        app.navigationBars.buttons["Готово"].tap()
        XCTAssertTrue(element(app, labelContaining: "Запустить MVP Linea").waitForExistence(timeout: 5), "Цель в плане")

        let field = openQuickAdd(app)
        field.tap()
        field.typeText("Запустить лендинг")
        let hint = chip(app, "Похоже, к цели")
        XCTAssertTrue(hint.waitForExistence(timeout: 5), "Похожая цель подсказывается в чипе")
        snapshot(app, "14 Подсказка цели")
        hint.tap()
        let link = app.buttons["Связать с целью «Запустить MVP Linea»"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        snapshot(app, "15 Меню цели")
        link.tap()
        XCTAssertTrue(chip(app, "Цель: Запустить MVP Linea").waitForExistence(timeout: 5), "Связь ставит человек")
        app.buttons["Добавить задачу"].tap()

        let explicit = openQuickAdd(app)
        explicit.tap()
        explicit.typeText("Подготовить релиз для цели MVP")
        XCTAssertTrue(chip(app, "Цель: Запустить MVP Linea").waitForExistence(timeout: 5), "«для цели …» связывает сразу")
        snapshot(app, "16 Цель названа словами")
        app.buttons["Добавить задачу"].tap()

        openTab(app, "План", index: 1)
        XCTAssertTrue(button(app, startingWith: "Подготовить релиз").waitForExistence(timeout: 5))
        snapshot(app, "17 План с целью")
    }

    // MARK: - 4. Карточка: тип задачи и «Сначала нужно»

    @MainActor
    func test4TaskCardKindAndDependencies() throws {
        let app = launch()
        addTask(app, "Собрать данные")
        addTask(app, "Написать отчёт, важно")

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
        let option = app.buttons["Собрать данные"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
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
        addTask(app, "Подготовить стратегию на полтора часа, важно")
        addTask(app, "Ответить на письма 15 минут")

        openTab(app, "Сегодня", index: 0)
        let headline = app.staticTexts["Сейчас — «Ответить на письма»."]
        XCTAssertTrue(headline.waitForExistence(timeout: 15), "До встречи 25 минут — сейчас короткое дело")
        let body = element(app, labelContaining: "её лучше после")
        XCTAssertTrue(body.exists, "Стратегия — после встречи")
        XCTAssertTrue(body.label.contains("«Подготовить стратегию» нужно 1 ч 30 мин"), body.label)
        XCTAssertTrue(body.label.contains("«Встреча с клиентом»"), body.label)
        scrollTo(headline, in: app)
        snapshot(app, "21 Сейчас: короткое дело до встречи")
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

    /// «3 октября» — как день подписан в календаре.
    static func dayMonth(daysFromNow days: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = appTimeZone
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: Date().addingTimeInterval(TimeInterval(days * 86_400)))
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

    @MainActor
    private func openTab(_ app: XCUIApplication, _ name: String, index: Int) {
        let named = app.tabBars.buttons[name]
        if named.waitForExistence(timeout: 3) {
            named.tap()
        } else {
            app.tabBars.buttons.element(boundBy: index).tap()
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

    // MARK: - Поиск

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
