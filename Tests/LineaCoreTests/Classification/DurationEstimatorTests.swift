import Testing
import Foundation
@testable import LineaCore

/// Оценка длительности, когда человек её не назвал: по словам, по типу
/// задачи и по истории — сколько похожие задачи заняли на самом деле.
/// Среда 9 сентября 2026, Москва.
@Suite("Оценка длительности")
struct DurationEstimatorTests {
    private let estimator = DurationEstimator()
    private let time = WowFixture.time(10)

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "D0000000-0000-0000-0000-%012d", n))!
    }

    private func rules(_ title: String) -> Int {
        estimator.estimate(title: title, kind: TaskClassifier().classify(title: title, goalID: nil).kind,
                           history: [], time: time).minutes
    }

    /// Закрытая задача: сколько заняла на самом деле и сколько дней назад.
    private func done(_ n: Int, _ title: String, actual: Int?, daysAgo: Int = 1) -> LineaTask {
        LineaTask(id: id(n), title: title, isDone: true, createdAt: WowFixture.created,
                  completedAt: WowFixture.moment(12, 0, dayOffset: -daysAgo), actualMinutes: actual)
    }

    // MARK: По словам

    @Test("Примеры заказчика: «Ответить клиенту» ~10 мин, «Подготовить презентацию» ~1 ч")
    func customerExamples() {
        let reply = estimator.estimate(title: "Ответить клиенту", kind: .incoming, history: [], time: time)
        #expect(reply == DurationEstimate(minutes: 10, source: .ai, samples: 0))
        #expect(QuickTaskText.duration(minutes: reply.minutes) == "~10 мин")
        let deck = estimator.estimate(title: "Подготовить презентацию", kind: .standalone, history: [], time: time)
        #expect(deck.minutes == 60)
        #expect(QuickTaskText.duration(minutes: deck.minutes) == "~1 ч")
    }

    @Test("Быстрое действие в начале решает за всё название; иначе — самое долгое из найденного")
    func wordsDecide() {
        #expect(rules("Отправить презентацию клиенту") == 10, "Отправить — быстро, презентация уже готова")
        #expect(rules("Оплатить интернет") == 10)
        #expect(rules("Позвонить маме") == 15)
        #expect(rules("Купить продукты") == 30)
        #expect(rules("Написать Ивану") == 15)
        #expect(rules("Написать статью для блога") == 90, "Статья — дольше, чем «написать»")
        #expect(rules("Подготовить стратегию") == 90)
        #expect(rules("Встреча с клиентом") == 60)
        #expect(rules("Разобрать почту") == 30)
        #expect(rules("Подготовить КП для клиента") == 60)
        // Слов из словаря нет — обычная для типа длительность.
        #expect(rules("Погулять с собакой") == TaskKind.standalone.typicalMinutes)
        #expect(estimator.estimate(title: "Погулять с собакой", kind: .goal, history: [], time: time).minutes == 60)
    }

    // MARK: По истории

    @Test("Три похожие задачи с известной длительностью — оценка по истории человека")
    func learnedFromSimilar() {
        let history = [
            done(1, "Ответить Ивану", actual: 20),
            done(2, "Ответить в чате", actual: 30),
            done(3, "Ответить бухгалтеру", actual: 25),
        ]
        let learned = estimator.estimate(title: "Ответить клиенту", kind: .incoming, history: history, time: time)
        #expect(learned == DurationEstimate(minutes: 25, source: .learned, samples: 3))

        // Двух мало; не начинали (длительность неизвестна), отменили, давно — не в счёт.
        var cancelled = done(4, "Ответить партнёру", actual: 40)
        cancelled.cancelledAt = WowFixture.moment(13, 0, dayOffset: -1)
        let thin = [history[0], history[1], done(5, "Ответить юристу", actual: nil), cancelled,
                    done(6, "Ответить подрядчику", actual: 50, daysAgo: 120)]
        #expect(estimator.estimate(title: "Ответить клиенту", kind: .incoming, history: thin, time: time).source == .ai)
    }

    @Test("Без слова из словаря — по задачам того же типа, но только с пяти")
    func learnedFromKind() {
        let walks = (1...5).map { done($0, "Погулять с собакой \($0)", actual: 40 + $0 * 2) }
        let learned = estimator.estimate(title: "Погулять с ребёнком", kind: .standalone, history: walks, time: time)
        #expect(learned.source == .learned)
        #expect(learned.minutes == 45, "Медиана 46 → 45")
        #expect(estimator.estimate(title: "Погулять с ребёнком", kind: .standalone, history: Array(walks.prefix(4)),
                                   time: time).source == .ai)
    }

    // MARK: Быстрый ввод и задача

    @Test("Быстрый ввод: серый чип — оценка Linea; сохраняется со своим источником")
    func quickCapture() throws {
        let history = (1...3).map { done($0, "Ответить коллеге \($0)", actual: 20) }
        func resolve(_ text: String) -> QuickTaskResolution {
            QuickTaskDraft(text: text).resolve(goals: [], profile: WowFixture.profile, time: time, history: history)
        }
        let reply = resolve("Ответить клиенту")
        #expect(reply.minutes == nil)
        #expect(reply.estimatedMinutes == 20)
        #expect(reply.durationSource == .learned)
        let task = reply.task(id: id(10), createdAt: time.now)
        #expect(task.estimatedMinutes == 20)
        #expect(task.estimatedDurationSource == .learned)
        #expect(task.userFields?.contains(.duration) == false)

        let said = resolve("Ответить клиенту 5 минут")
        #expect(said.durationSource == .user)
        #expect(said.task(id: id(11), createdAt: time.now).estimatedDurationSource == .user)
        #expect(said.estimate == nil, "Сказанное — не оценивается")
    }

    @Test("План: оценка по истории — уже реальное время, её не растягивает поправка калибровки")
    func planDuration() {
        var calibration = Calibration.default
        calibration.estimateMultiplier = 1.5
        var learned = LineaTask(title: "Ответить клиенту", estimatedMinutes: 20, estimatedDurationSource: .learned)
        #expect(PlanDuration.minutes(for: learned, calibration: calibration) == 20)
        learned.estimatedDurationSource = .ai
        #expect(PlanDuration.minutes(for: learned, calibration: calibration) == 30)
        learned.estimatedDurationSource = .user
        #expect(PlanDuration.minutes(for: learned, calibration: calibration) == 30, "Люди недооценивают свои задачи")
    }

    @Test("Переименовали — оценка Linea следует за названием; выбор человека и старые задачи — нет")
    func renameFollowsTitle() {
        let call = LineaTask(title: "Позвонить Пете", createdAt: WowFixture.created, estimatedMinutes: 15,
                             cognitiveDemand: .normal, userFields: [], estimatedDurationSource: .ai)
        var renamed = call
        renamed.title = "Подготовить стратегию для Пети"
        let saved = TaskOwnership.saved(previous: call, updated: renamed)
        #expect(saved.estimatedMinutes == 90)
        #expect(saved.estimatedDurationSource == .ai)

        var own = call
        own.estimatedMinutes = 20
        own.estimatedDurationSource = .user
        own.userFields = [.duration]
        var ownRenamed = own
        ownRenamed.title = "Подготовить стратегию для Пети"
        #expect(TaskOwnership.saved(previous: own, updated: ownRenamed).estimatedMinutes == 20)

        let legacy = LineaTask(title: "Позвонить Пете", createdAt: WowFixture.created, estimatedMinutes: 15)
        var legacyRenamed = legacy
        legacyRenamed.title = "Подготовить стратегию для Пети"
        #expect(TaskOwnership.saved(previous: legacy, updated: legacyRenamed).estimatedMinutes == 15)
    }

    @Test("Человек поменял длительность одним тапом — она его; в карточке видно, чья оценка")
    func userChangesEstimate() {
        let task = LineaTask(title: "Ответить клиенту", createdAt: WowFixture.created, estimatedMinutes: 10,
                             userFields: [], estimatedDurationSource: .ai)
        #expect(DurationText.estimate(of: task) == "~10 мин — оценка Linea")
        var learned = task
        learned.estimatedMinutes = 25
        learned.estimatedDurationSource = .learned
        #expect(DurationText.estimate(of: learned) == "~25 мин — по твоим похожим задачам")

        var tapped = task
        tapped.estimatedMinutes = 30
        let saved = TaskOwnership.saved(previous: task, updated: tapped)
        #expect(saved.estimatedDurationSource == .user)
        #expect(saved.isSetByUser(.duration))
        #expect(DurationText.estimate(of: saved) == nil)

        // Тапнул ту же длительность, что оценила Linea, — теперь она его.
        let thirty = LineaTask(title: "Проверить сборку", createdAt: WowFixture.created, estimatedMinutes: 30,
                               userFields: [], estimatedDurationSource: .ai)
        var confirmed = thirty
        confirmed.estimatedDurationSource = .user
        confirmed.userFields?.insert(.duration)
        let kept = TaskOwnership.saved(previous: thirty, updated: confirmed)
        #expect(kept.isSetByUser(.duration))
        #expect(kept.estimatedDurationSource == .user)
    }

    @Test("Задача, сохранённая до оценки Linea, читается: источника нет, своя длительность — человека")
    func legacyDecode() throws {
        let json = #"{"id":"\#(id(1).uuidString)","title":"Отчёт","createdAt":800000000,"estimatedMinutes":45}"#
        let task = try JSONDecoder().decode(LineaTask.self, from: Data(json.utf8))
        #expect(task.estimatedDurationSource == nil)
        #expect(!task.isDurationEstimatedByLinea)
        #expect(DurationText.estimate(of: task) == nil)
    }
}
