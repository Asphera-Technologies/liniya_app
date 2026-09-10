import Testing
import Foundation
@testable import LineaCore

@Suite("Русский текст")
struct RussianTextTests {
    @Test("Склонение числительных")
    func plural() {
        func noun(_ n: Int) -> String {
            RussianText.plural(n, "приоритетное действие", "приоритетных действия", "приоритетных действий")
        }
        #expect(noun(1) == "приоритетное действие")
        #expect(noun(2) == "приоритетных действия")
        #expect(noun(4) == "приоритетных действия")
        #expect(noun(5) == "приоритетных действий")
        #expect(noun(11) == "приоритетных действий")
        #expect(noun(12) == "приоритетных действий")
        #expect(noun(14) == "приоритетных действий")
        #expect(noun(21) == "приоритетное действие")
        #expect(noun(22) == "приоритетных действия")
        #expect(noun(105) == "приоритетных действий")
        #expect(noun(0) == "приоритетных действий")
    }

    @Test("Длительность в минутах")
    func duration() {
        #expect(RussianText.duration(minutes: 0) == "0 мин")
        #expect(RussianText.duration(minutes: 5) == "5 мин")
        #expect(RussianText.duration(minutes: 45) == "45 мин")
        #expect(RussianText.duration(minutes: 60) == "1 ч")
        #expect(RussianText.duration(minutes: 65) == "1 ч 5 мин")
        #expect(RussianText.duration(minutes: 80) == "1 ч 20 мин")
        #expect(RussianText.duration(minutes: 120) == "2 ч")
        #expect(RussianText.duration(minutes: 125) == "2 ч 5 мин")
    }

    @Test("Часы и минуты сна")
    func hoursMinutes() {
        #expect(RussianText.hoursMinutes(seconds: 21_780) == "6:03")
        #expect(RussianText.hoursMinutes(seconds: 2_700) == "0:45")
        #expect(RussianText.hoursMinutes(seconds: 25_980) == "7:13")
        #expect(RussianText.hoursMinutes(seconds: 0) == "0:00")
    }

    @Test("Время суток берётся из календаря контекста")
    func clock() {
        #expect(RussianText.clock(WowFixture.moment(12), time: WowFixture.morning) == "12:00")
        #expect(RussianText.clock(WowFixture.moment(15, 50), time: WowFixture.morning) == "15:50")
        // Тот же момент в UTC — другой час: календарь действительно инъектируется.
        let utc = TimeContext(now: WowFixture.morning.now, timeZoneIdentifier: "UTC")
        #expect(RussianText.clock(WowFixture.moment(12), time: utc) == "9:00")
    }

    @Test("Приветствие по часу")
    func greeting() {
        #expect(RussianText.greeting(hour: 8) == "Доброе утро")
        #expect(RussianText.greeting(hour: 14) == "Добрый день")
        #expect(RussianText.greeting(hour: 20) == "Добрый вечер")
        #expect(RussianText.greeting(hour: 3) == "Доброй ночи")
    }
}
