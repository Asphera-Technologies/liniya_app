import Testing
import Foundation
@testable import LineaCore

@Suite("Аналитика сна")
struct SleepInsightTests {
    private let builder = SleepInsightBuilder()
    private let config = EngineConfig.default

    @Test("Неделя сравнивается с личной нормой")
    func weekVsUsual() {
        let insight = builder.build(history: WowFixture.history, today: nil, config: config, time: WowFixture.morning)
        #expect(insight.recentNights.count == 7)
        #expect(insight.usualSeconds == 25_980)
        #expect(insight.weekAverageSeconds != nil)
        #expect(insight.canCompare)
        // Ровный график фикстуры: неделя близка к норме.
        #expect(abs(insight.deltaSeconds ?? 0) < 1200)
    }

    @Test("Сегодняшняя короткая ночь попадает в неделю, но не в норму")
    func todayIsNotBaseline() {
        let today = DailyHealthSummary(day: WowFixture.today, values: [
            .sleepAsleep: 21_780, .sleepInBed: 24_000, .sleepBedtime: 57,
        ])
        let insight = builder.build(history: WowFixture.history, today: today, config: config, time: WowFixture.morning)
        #expect(insight.recentNights.last?.asleepSeconds == 21_780)
        #expect(insight.usualSeconds == 25_980)      // норма не сдвинулась
        #expect((insight.deltaSeconds ?? 0) < 0)     // неделя ниже нормы
    }

    @Test("Стабильность отбоя — разброс вокруг медианы")
    func bedtimeStability() {
        let insight = builder.build(history: WowFixture.history, today: nil, config: config, time: WowFixture.morning)
        #expect(insight.bedtimeStabilityMinutes != nil)
        #expect(insight.bedtimeStabilityMinutes! < 30)
    }

    @Test("Эффективность считается только когда известно время в кровати")
    func efficiency() {
        let insight = builder.build(history: WowFixture.history, today: nil, config: config, time: WowFixture.morning)
        #expect(insight.weekEfficiency != nil)
        #expect(insight.weekEfficiency! > 0.8 && insight.weekEfficiency! <= 1)

        let withoutInBed = WowFixture.history.map { summary -> DailyHealthSummary in
            var copy = summary
            copy[.sleepInBed] = nil
            return copy
        }
        #expect(builder.build(history: withoutInBed, today: nil, config: config, time: WowFixture.morning).weekEfficiency == nil)
    }

    @Test("Мало данных — сравнивать нельзя, и это видно")
    func coldStart() {
        let short = Array(WowFixture.history.suffix(3))
        let insight = builder.build(history: short, today: nil, config: config, time: WowFixture.morning)
        #expect(insight.recentNights.count == 3)
        #expect(insight.baselineProgress?.days == 3)
        #expect(insight.canCompare == false)
    }

    @Test("Совсем без данных возвращается пустая аналитика")
    func empty() {
        let insight = builder.build(history: [], today: nil, config: config, time: WowFixture.morning)
        #expect(insight.recentNights.isEmpty)
        #expect(insight.usualSeconds == nil)
        #expect(insight.canCompare == false)
    }
}
