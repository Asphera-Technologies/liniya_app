import Testing
import Foundation
@testable import LineaCore

@Suite("Сон для Linea AI")
struct SleepContextTextTests {
    private let time = WowFixture.morning

    private func night(stages: [SleepStage: TimeInterval], quality: Double = 1, inBed: TimeInterval = 26_400) -> SleepNight {
        SleepNight(
            day: WowFixture.moment(0),
            bedtime: WowFixture.moment(23, 50, dayOffset: -1),
            wakeTime: WowFixture.moment(7, 10),
            asleepSeconds: 24_000,
            inBedSeconds: inBed,
            stages: stages,
            quality: quality,
            sourceName: "watch",
            awakenings: 2
        )
    }

    private var staged: SleepNight {
        night(stages: [.deep: 3_900, .rem: 5_400, .core: 14_700, .awake: 900])
    }

    @Test("Ночь: длительность, отбой и подъём, кровать, эффективность, пробуждения")
    func nightLine() {
        #expect(SleepContextText.nightLine(staged, time: time)
            == "Сон прошлой ночью: 6 ч 40 мин, с 23:50 до 7:10; в кровати 7 ч 20 мин; эффективность 91%; пробуждений: 2.")
    }

    @Test("Фазы — с долями от сна по фазам и бодрствованием")
    func stages() {
        #expect(SleepContextText.stagesLine(staged)
            == "Фазы сна: глубокий 1 ч 5 мин (16%), быстрый (REM) 1 ч 30 мин (23%), базовый 4 ч 5 мин (61%); бодрствование ночью 15 мин.")
    }

    @Test("Без фаз — сказано прямо, чтобы модель их не придумывала")
    func noStages() {
        #expect(SleepContextText.stagesLine(night(stages: [:], quality: 0.8))
            == "Фаз сна в данных нет: источник записывает только время сна, без фаз.")
    }

    @Test("Только «в кровати» — ночь помечена как оценка")
    func inBedOnly() {
        let line = SleepContextText.nightLine(night(stages: [:], quality: 0.5), time: time)
        #expect(!line.contains("эффективность"), "Эффективность из оценки — не факт")
        #expect(line.hasSuffix("Сон оценён по времени в кровати: источник не отличает сон от бодрствования."))
    }

    @Test("Оценка сна — компонент движка состояния, из 100, с уровнем к обычному")
    func score() {
        let component = StateComponent(kind: .sleep, score: 0.72, confidence: 0.9, level: .belowUsual)
        #expect(SleepContextText.scoreLine(component)
            == "Оценка сна Linea: 72 из 100 (длительность относительно нормы, эффективность и недосып за неделю); ниже обычного.")
        #expect(SleepContextText.scoreLine(StateComponent(kind: .recovery, score: 0.5, confidence: 1)) == nil)
    }

    @Test("Неделя: среднее, норма, эффективность, отбой и ночи по дням")
    func week() {
        let insight = SleepInsightBuilder().build(history: WowFixture.history, today: nil, config: .default, time: time)
        let lines = SleepContextText.weekLines(insight, time: time)
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("Сон за неделю в среднем "))
        #expect(lines[0].contains("обычно "))
        #expect(lines[0].contains("средняя эффективность "))
        #expect(lines[1].hasPrefix("Ночи за неделю: "))
        #expect(lines[1].components(separatedBy: "; ").count == 7)
    }

    @Test("Контекст целиком: ночь, фазы, оценка, неделя")
    func context() {
        let insight = SleepInsightBuilder().build(history: WowFixture.history, today: nil, config: .default, time: time)
        let component = StateComponent(kind: .sleep, score: 0.8, confidence: 1, level: .usual)
        let lines = SleepContextText.contextLines(night: staged, component: component, insight: insight, time: time)
        #expect(lines.count == 5)
        #expect(lines[1].hasPrefix("Фазы сна: глубокий"))
        #expect(lines[2].hasPrefix("Оценка сна Linea: 80 из 100"))
        #expect(SleepContextText.contextLines(night: nil, component: nil, insight: .empty, time: time).isEmpty)
    }

    @Test("Ответ без модели: ночь с фазами и неделя")
    func offlineAnswer() {
        let insight = SleepInsightBuilder().build(history: WowFixture.history, today: nil, config: .default, time: time)
        let answer = SleepContextText.answer(night: staged, insight: insight, time: time)
        #expect(answer?.hasPrefix("Прошлой ночью — 6 ч 40 мин, с 23:50 до 7:10. Фазы: глубокий 1 ч 5 мин, быстрый 1 ч 30 мин, базовый 4 ч 5 мин. За неделю в среднем ") == true)
        #expect(SleepContextText.answer(night: nil, insight: .empty, time: time) == nil)
    }
}
