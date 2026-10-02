import Testing
import Foundation
@testable import LineaCore

@Suite("Тип задачи")
struct TaskClassifierTests {
    private let classifier = TaskClassifier()

    private func kind(_ title: String, goal: UUID? = nil, fixed: Bool = false, demand: CognitiveDemand? = nil) -> TaskKind {
        classifier.classify(title: title, goalID: goal, isFixed: fixed, demand: demand).kind
    }

    @Test("Примеры из постановки")
    func examplesFromBrief() {
        #expect(kind("Подготовить релиз") == .goal)
        #expect(kind("Отправить документ клиенту") == .obligation)
        #expect(kind("Оплатить интернет") == .maintenance)
        #expect(kind("Купить продукты") == .maintenance)
        #expect(kind("Позвонить другу") == .standalone)
        #expect(kind("Разобрать входящие") == .routine)
    }

    @Test("Входящее — реакция на конкретное; разбор потока — рутина")
    func incomingVersusRoutine() {
        #expect(kind("Ответить Ивану") == .incoming)
        #expect(kind("Перезвонить в банк") == .incoming)
        #expect(kind("Рассмотреть заявку от отдела") == .incoming)
        #expect(kind("Ответить на письма") == .routine)
        #expect(kind("Разобрать почту") == .routine)
        #expect(kind("Спланировать неделю") == .routine)
    }

    @Test("Связь с целью и выбор человека сильнее слов")
    func goalAndOverride() {
        let goal = WowFixture.goalMVP
        #expect(kind("Купить продукты", goal: goal) == .goal)
        let chosen = classifier.classify(title: "Купить продукты", goalID: goal, override: .routine)
        #expect(chosen.kind == .routine)
        #expect(chosen.reason == .chosen)
        #expect(chosen.confidence == 1)
        let task = LineaTask(title: "Оплатить интернет", kindOverride: .obligation)
        #expect(classifier.kind(of: task) == .obligation)
    }

    @Test("Время тянет к обязательству, но привычка остаётся привычкой")
    func fixedTime() {
        #expect(kind("Созвон с командой", fixed: true) == .obligation)
        #expect(kind("Тренировка", fixed: true) == .routine)
        let meeting = classifier.classify(title: "Иван", goalID: nil, isFixed: true)
        #expect(meeting.kind == .obligation)
        #expect(meeting.reason == .fixedTime)
    }

    @Test("Личное слабее рабочего: «позвонить клиенту» — обязательство, «подарок маме» — разовое")
    func personalWeights() {
        #expect(kind("Позвонить клиенту") == .obligation)
        #expect(kind("Купить подарок маме") == .standalone)
        #expect(kind("Поздравить сестру с днём рождения") == .standalone)
    }

    @Test("Без признаков: сложная — шаг к цели, иначе разовое, уверенность низкая")
    func fallback() {
        let plain = classifier.classify(title: "Подумать", goalID: nil)
        #expect(plain.kind == .standalone)
        #expect(plain.reason == .fallback)
        #expect(plain.confidence < 0.5)
        let deep = classifier.classify(title: "Подумать", goalID: nil, demand: .deep)
        #expect(deep.kind == .goal)
        #expect(deep.reason == .deepWork)
    }

    @Test("Уверенность: много признаков — выше, спорные — ниже, причина — слово")
    func confidence() {
        let strong = classifier.classify(title: "Отправить договор клиенту", goalID: nil)
        #expect(strong.kind == .obligation)
        #expect(strong.confidence >= 0.9)
        #expect(strong.reason == .keyword("отправить"))
        // «Ответить клиенту»: входящее против обязательства — равный вес.
        let disputed = classifier.classify(title: "Ответить клиенту", goalID: nil)
        #expect(disputed.kind == .incoming)
        #expect(disputed.confidence < strong.confidence)
    }

    @Test("Задачи wow-сценария")
    func wowTasks() {
        let kinds = Dictionary(uniqueKeysWithValues: WowFixture.tasks.map { ($0.id, classifier.kind(of: $0)) })
        #expect(kinds[WowFixture.taskA] == .goal)
        #expect(kinds[WowFixture.taskB] == .goal)
        #expect(kinds[WowFixture.taskC] == .routine)
        #expect(kinds[WowFixture.taskCall] == .obligation)
        #expect(kinds[WowFixture.taskWorkout] == .routine)
    }

    @Test("Длительность: оценка человека, иначе обычная для типа")
    func estimate() {
        #expect(TaskEstimate.minutes(for: LineaTask(title: "Оплатить интернет")) == 30)
        #expect(TaskEstimate.minutes(for: LineaTask(title: "Ответить Ивану")) == 15)
        #expect(TaskEstimate.minutes(for: LineaTask(title: "Подготовить релиз")) == 60)
        #expect(TaskEstimate.minutes(for: LineaTask(title: "Подготовить релиз", estimatedMinutes: 120)) == 120)
        #expect(TaskEstimate.minutes(for: LineaTask(title: "Позвонить", estimatedMinutes: 1)) == 5)
        // Цель меняет тип, а с ним и оценку.
        #expect(TaskEstimate.minutes(for: LineaTask(title: "Купить продукты", goalID: WowFixture.goalMVP)) == 60)
    }

    @Test("Быстрый ввод: тип даёт сложность и серую оценку длительности")
    func quickCapture() {
        func resolve(_ text: String) -> QuickTaskResolution {
            QuickTaskDraft(text: text).resolve(goals: WowFixture.goals, profile: WowFixture.profile, time: WowFixture.morning)
        }
        let bills = resolve("Оплатить интернет")
        #expect(bills.kind == .maintenance)
        #expect(bills.demand == .light)
        #expect(bills.minutes == nil)
        #expect(bills.estimatedMinutes == 30)
        let release = resolve("Подготовить релиз для цели MVP")
        #expect(release.kind == .goal)
        #expect(release.demand == .deep)
        #expect(release.estimatedMinutes == 60)
        // Сказанное сильнее типа.
        let quick = resolve("Подготовить релиз быстро на 20 минут")
        #expect(quick.demand == .light)
        #expect(quick.estimatedMinutes == 20)
        // Тип не хранится в задаче — его вычисляет Linea.
        #expect(bills.task(id: WowFixture.taskA, createdAt: WowFixture.morning.now).kindOverride == nil)
    }

    @Test("Тип и правка типа переживают сохранение в JSON")
    func codable() throws {
        let task = LineaTask(title: "Оплатить интернет", kindOverride: .routine)
        let decoded = try JSONDecoder().decode(LineaTask.self, from: JSONEncoder().encode(task))
        #expect(decoded.kindOverride == .routine)
        // Старая запись без поля читается.
        let legacy = try JSONEncoder().encode(LineaTask(title: "Старая"))
        var object = try #require(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
        object.removeValue(forKey: "kindOverride")
        let old = try JSONDecoder().decode(LineaTask.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.kindOverride == nil)
    }
}
