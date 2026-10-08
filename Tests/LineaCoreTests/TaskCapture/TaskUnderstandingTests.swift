import Testing
import Foundation
@testable import LineaCore

/// AI-разбор введённой задачи: пример заказчика целиком и три правила —
/// не уверен — пусто; сказанный приоритет — приоритет человека; что человек
/// поменял руками, Linea сама не перезаписывает. Время — среда 9 сентября
/// 2026, 08:00 по Москве: «завтра» — четверг 10-го.
@Suite("AI-разбор задачи")
struct TaskUnderstandingTests {
    private let time = WowFixture.morning
    private static let example = "Завтра до обеда подготовить КП для клиента, часа на полтора, высокий приоритет."

    private func resolve(_ draft: QuickTaskDraft, goals: [LineaGoal] = []) -> QuickTaskResolution {
        draft.resolve(goals: goals, profile: WowFixture.profile, time: time)
    }

    private var tomorrow: Date { WowFixture.calendar.startOfDay(for: WowFixture.moment(12, 0, dayOffset: 1)) }

    // MARK: Пример заказчика

    @Test("Пример заказчика: название, завтра, до 12:00, полтора часа, высокий")
    func customerExample() {
        let parse = QuickTaskParser().parse(Self.example, profile: WowFixture.profile, time: time)
        #expect(parse.title == "Подготовить КП для клиента")
        #expect(parse.day == .tomorrow)
        #expect(parse.deadline == WowFixture.moment(12, 0, dayOffset: 1))
        #expect(parse.minutes == 90)
        #expect(parse.priority == .important)
        #expect(parse.startTime == nil)
        #expect(parse.recognized.map(\.text) == ["высокий приоритет", "до обеда", "Завтра", "часа на полтора"])

        let result = resolve(QuickTaskDraft(text: Self.example))
        #expect(result.isUnderstood)
        #expect(result.title == "Подготовить КП для клиента")
        #expect(QuickTaskText.summary(result, time: time) == "Завтра · до 12:00 · ~1 ч 30 мин · Высокий")

        let task = result.task(id: WowFixture.taskA, createdAt: time.now)
        #expect(task.title == "Подготовить КП для клиента")
        #expect(task.date == tomorrow)
        #expect(task.deadline == WowFixture.moment(12, 0, dayOffset: 1))
        #expect(task.estimatedMinutes == 90)
        #expect(task.priority == .important)
        #expect(task.scheduledStart == nil)
        #expect(task.goalID == nil)
    }

    @Test("«До обеда» — до 12:00, «к обеду» — тоже")
    func beforeLunch() {
        let parser = QuickTaskParser()
        #expect(parser.parse("Отчёт до обеда", profile: WowFixture.profile, time: time).deadline == WowFixture.moment(12))
        #expect(parser.parse("Отчёт к обеду", profile: WowFixture.profile, time: time).deadline == WowFixture.moment(12))
        let adjective = parser.parse("Подготовить КП для клиента к завтрашнему обеду", profile: WowFixture.profile, time: time)
        #expect(adjective.deadline == WowFixture.moment(12, 0, dayOffset: 1))
        #expect(adjective.title == "Подготовить КП для клиента")
        #expect(parser.parse("Отчёт до сегодняшнего вечера", profile: WowFixture.profile, time: time).deadline == WowFixture.moment(18))
        // После полудня «до обеда» без дня — уже завтра.
        let late = parser.parse("Отчёт до обеда", profile: WowFixture.profile, time: WowFixture.time(14))
        #expect(late.deadline == WowFixture.moment(12, 0, dayOffset: 1))
    }

    // MARK: Правило 1: не уверен — пусто

    @Test("Ничего не сказано о параметрах — ничего и не придумано")
    func nothingInvented() {
        let result = resolve(QuickTaskDraft(text: "Подготовить КП для клиента"))
        #expect(!result.isUnderstood)
        #expect(result.date == nil)
        #expect(result.deadline == nil)
        #expect(result.minutes == nil)
        #expect(result.priorityOrigin == .assumed)
        #expect(QuickTaskText.summary(result, time: time) == "")
        let task = result.task(id: WowFixture.taskA, createdAt: time.now)
        #expect(task.estimatedMinutes == nil, "Обычная длительность не записывается в задачу — её считает план")
        #expect(task.userFields == [])
    }

    @Test("Опора на слова: значение без куска строки не принимается")
    func groundedValues() {
        // Как ответила бы модель, которая додумала: приоритета и срока в строке нет.
        let invented = QuickTaskParse(
            title: "Подготовить КП", deadline: WowFixture.moment(18), minutes: 120, priority: .important,
            recognized: [QuickTaskParse.Recognized(part: .duration, text: "на два часа")]
        )
        let grounded = invented.grounded(in: "Подготовить КП")
        #expect(grounded.priority == nil)
        #expect(grounded.deadline == nil)
        #expect(grounded.minutes == nil, "«на два часа» в строке нет — опоры нет")
        #expect(grounded.recognized.isEmpty)
        #expect(grounded.title == "Подготовить КП")

        // Название из слов, которых человек не говорил, — остаётся сказанное.
        let rephrased = QuickTaskParse(title: "Подготовить коммерческое предложение")
        #expect(rephrased.grounded(in: "подготовить кп завтра").title == "Подготовить кп завтра")

        // Правила работают так по построению: проверка ничего не меняет.
        let parse = QuickTaskParser().parse(Self.example, profile: WowFixture.profile, time: time)
        #expect(parse.grounded(in: Self.example) == parse)
        let someday = QuickTaskParser().parse("Купить книгу когда-нибудь", profile: WowFixture.profile, time: time)
        #expect(someday.grounded(in: "Купить книгу когда-нибудь") == someday)
        #expect(someday.day == .someday)
    }

    // MARK: Правило 2: сказанный приоритет — приоритет человека

    @Test("«Высокий приоритет» сказан — это приоритет человека; не сказан — нет")
    func spokenPriorityIsTheUsers() {
        let said = resolve(QuickTaskDraft(text: Self.example)).task(id: WowFixture.taskA, createdAt: time.now)
        #expect(said.userFields == [.day, .deadline, .duration, .priority])
        #expect(said.isSetByUser(.priority))

        let silent = resolve(QuickTaskDraft(text: "Подготовить КП для клиента")).task(id: WowFixture.taskB, createdAt: time.now)
        #expect(silent.priority == .normal)
        #expect(!silent.isSetByUser(.priority), "«Средний» по умолчанию — не выбор человека")
        #expect(!silent.isSetByUser(.demand), "Сложность подставила Linea")
    }

    @Test("Выбор в чипе — тоже человека, в том числе «Без даты» и «Без цели»")
    func chosenIsTheUsers() {
        var draft = QuickTaskDraft(text: "Отчёт к пятнице")
        let deadlineOnly = resolve(draft).task(id: WowFixture.taskA, createdAt: time.now)
        #expect(deadlineOnly.userFields == [.deadline], "Срок назван, день — нет")

        draft = QuickTaskDraft(text: "Отчёт", day: .someday, minutes: 45, priority: .low, goal: .noGoal)
        let chosen = resolve(draft, goals: WowFixture.goals).task(id: WowFixture.taskB, createdAt: time.now)
        #expect(chosen.userFields == [.day, .duration, .priority, .goal])

        let hard = resolve(QuickTaskDraft(text: "Сложная презентация")).task(id: WowFixture.taskC, createdAt: time.now)
        #expect(hard.userFields == [.demand])
        #expect(hard.cognitiveDemand == .deep)
    }

    // MARK: Правило 3: правку человека Linea не перезаписывает

    @Test("Сохранённая задача: человек поменял приоритет — повторный разбор его не трогает")
    func manualChangeSurvivesUnderstanding() {
        let saved = resolve(QuickTaskDraft(text: Self.example)).task(id: WowFixture.taskA, createdAt: time.now)
        // Человек открыл карточку и сделал задачу средней и на час.
        var edited = saved
        edited.priority = .normal
        edited.estimatedMinutes = 60
        let stored = TaskOwnership.saved(previous: saved, updated: edited)
        #expect(stored.priority == .normal)
        #expect(stored.userFields == [.day, .deadline, .duration, .priority])

        // Linea снова поняла задачу (как это сделала бы модель) — и хочет вернуть своё.
        let proposal = TaskProposal(
            date: WowFixture.today, deadline: WowFixture.moment(18), estimatedMinutes: 90,
            priority: .important, goalID: WowFixture.goalMVP, demand: .deep
        )
        let (result, applied) = TaskOwnership.applying(proposal, to: stored)
        #expect(result.priority == .normal, "Приоритет поменял человек")
        #expect(result.estimatedMinutes == 60)
        #expect(result.date == tomorrow)
        #expect(result.deadline == WowFixture.moment(12, 0, dayOffset: 1))
        // Цели и сложности человек не касался — их Linea менять может.
        #expect(result.goalID == WowFixture.goalMVP)
        #expect(result.cognitiveDemand == .deep)
        #expect(applied == [.goal, .demand])
    }

    @Test("Что поменял человек — его; что задал раньше — его и остаётся")
    func userEditsAccumulate() {
        let base = LineaTask(title: "Отчёт", createdAt: WowFixture.created, userFields: [.priority])
        var moved = base
        moved.date = WowFixture.today
        moved.estimatedMinutes = 30
        let stored = TaskOwnership.userEdited(previous: base, updated: moved)
        #expect(stored.userFields == [.priority, .day, .duration])
        #expect(TaskOwnership.changedFields(from: base, to: moved) == [.day, .duration])

        // Отметка «Готово» — не параметр.
        var done = stored
        done.isDone = true
        done.completedAt = WowFixture.moment(10)
        #expect(TaskOwnership.userEdited(previous: stored, updated: done).userFields == stored.userFields)
    }

    @Test("Задача, сохранённая раньше правила, — вся человека: Linea её сама не меняет")
    func legacyTaskIsUntouchable() {
        let legacy = LineaTask(title: "Позвонить Пете", createdAt: WowFixture.created)
        #expect(legacy.userFields == nil)
        #expect(TaskField.allCases.allSatisfy(legacy.isSetByUser))
        let (result, applied) = TaskOwnership.applying(TaskProposal(priority: .important, demand: .deep), to: legacy)
        #expect(applied.isEmpty)
        #expect(result == legacy)
        var renamed = legacy
        renamed.title = "Подготовить стратегию для Пети"
        #expect(TaskOwnership.saved(previous: legacy, updated: renamed).cognitiveDemand == .normal)
        #expect(TaskOwnership.saved(previous: legacy, updated: renamed).userFields == nil)
    }

    @Test("Переименовали — сложность Linea следует за названием, сложность человека — нет")
    func demandFollowsTitle() {
        let quick = resolve(QuickTaskDraft(text: "Позвонить Пете")).task(id: WowFixture.taskA, createdAt: time.now)
        #expect(quick.cognitiveDemand == .normal)
        var renamed = quick
        renamed.title = "Подготовить стратегию для Пети"
        #expect(TaskOwnership.saved(previous: quick, updated: renamed).cognitiveDemand == .deep)

        var light = quick
        light.title = "Быстро подготовить стратегию"
        #expect(TaskOwnership.saved(previous: quick, updated: light).cognitiveDemand == .light, "«быстро» в названии")

        // Человек сам выбрал сложность — она остаётся, что бы ни было в названии.
        var chosen = quick
        chosen.cognitiveDemand = .light
        let stored = TaskOwnership.saved(previous: quick, updated: chosen)
        var renamedAgain = stored
        renamedAgain.title = "Подготовить стратегию для Пети"
        #expect(TaskOwnership.saved(previous: stored, updated: renamedAgain).cognitiveDemand == .light)
    }

    // MARK: Строка задачи

    @Test("Строка задачи: только заданное, без значений по умолчанию")
    func taskSummary() {
        let task = resolve(QuickTaskDraft(text: Self.example)).task(id: WowFixture.taskA, createdAt: time.now)
        #expect(QuickTaskText.summary(of: task, time: time) == "Завтра · до 12:00 · ~1 ч 30 мин · Высокий")
        // В «Плане» день — в заголовке раздела, приоритет — справа в строке.
        #expect(QuickTaskText.summary(of: task, time: time, includesDay: false, includesPriority: false) == "до 12:00 · ~1 ч 30 мин")

        let plain = LineaTask(title: "Оплатить интернет", createdAt: WowFixture.created, userFields: [])
        #expect(QuickTaskText.summary(of: plain, time: time) == "")

        let call = LineaTask(title: "Созвон", date: WowFixture.today, createdAt: WowFixture.created,
                             deadline: WowFixture.moment(21, 0, dayOffset: 2), scheduledStart: WowFixture.moment(15, 50),
                             estimatedMinutes: 30)
        #expect(QuickTaskText.summary(of: call, time: time) == "Сегодня · в 15:50 · до пт, 11 сен · ~30 мин")

        // «Средний», сказанный словами, — тоже задан.
        var normal = plain
        normal.userFields = [.priority]
        #expect(QuickTaskText.summary(of: normal, time: time) == "Средний")
        let low = LineaTask(title: "Разобрать фото", priority: .low, createdAt: WowFixture.created)
        #expect(QuickTaskText.summary(of: low, time: time) == "Низкий")
    }

    @Test("Строка быстрого ввода: выбранное в чипах — да, подставленное Linea — нет")
    func draftSummary() {
        var draft = QuickTaskDraft(text: "Отчёт на неделе")
        #expect(QuickTaskText.summary(resolve(draft), time: time) == "На неделе")
        draft.minutes = 45
        #expect(QuickTaskText.summary(resolve(draft), time: time) == "На неделе · ~45 мин")
        draft.deadline = .at(WowFixture.moment(18))
        #expect(QuickTaskText.summary(resolve(draft), time: time) == "до 18:00 · ~45 мин")

        let start = resolve(QuickTaskDraft(text: "Созвон в 15:00"))
        #expect(QuickTaskText.summary(start, time: time) == "Сегодня · в 15:00")
        // Служебное вырезано, параметров нет: Linea поняла, но строка пустая.
        let filler = resolve(QuickTaskDraft(text: "Добавь задачу купить хлеб"))
        #expect(filler.isUnderstood)
        #expect(filler.title == "Купить хлеб")
        #expect(QuickTaskText.summary(filler, time: time) == "")
        // Одно «завтра» — название то же, показывать «как поняла» нечего.
        let bare = resolve(QuickTaskDraft(text: "завтра"))
        #expect(bare.title == "Завтра")
        #expect(bare.day == .tomorrow)
        #expect(!bare.isUnderstood)
    }

    @Test("Старая запись дня без отметок человека читается: всё считается заданным им")
    func legacyRecordDecodes() throws {
        let encoder = JSONEncoder()
        let task = LineaTask(title: "Отчёт", createdAt: WowFixture.created, userFields: [.priority, .day])
        let data = try encoder.encode(task)
        let decoded = try JSONDecoder().decode(LineaTask.self, from: data)
        #expect(decoded.userFields == [.priority, .day])

        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "userFields")
        let legacy = try JSONDecoder().decode(LineaTask.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.userFields == nil)
        #expect(legacy.isSetByUser(.goal))
    }
}
