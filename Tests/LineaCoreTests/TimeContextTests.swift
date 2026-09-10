import Testing
import Foundation
@testable import LineaCore

@Suite("TimeContext")
struct TimeContextTests {
    @Test("Local hour follows the injected calendar, not the container's UTC")
    func localHour() {
        let t = WowFixture.afternoon
        #expect(t.timeOfDay(of: t.now) == TimeOfDay(hour: 14, minute: 30))
        #expect(abs(t.hourFraction(of: t.now) - 14.5) < 0.001)
        let utc = TimeContext(now: t.now, timeZoneIdentifier: "UTC")
        #expect(utc.timeOfDay(of: t.now) == TimeOfDay(hour: 11, minute: 30))
    }

    @Test("Day helpers")
    func dayHelpers() {
        let t = WowFixture.morning
        #expect(t.today == WowFixture.today)
        #expect(t.date(on: WowFixture.today, at: TimeOfDay(hour: 15, minute: 50)) == WowFixture.moment(15, 50))
        #expect(t.days(from: WowFixture.moment(23, 59, dayOffset: -2), to: t.now) == 2)
        #expect(t.dayInterval(containing: t.now).duration == 86_400)
    }

    @Test("Quiet hours span midnight")
    func quietHours() {
        let p = UserProfile()
        #expect(p.isQuiet(TimeOfDay(hour: 23)))
        #expect(p.isQuiet(TimeOfDay(hour: 3)))
        #expect(!p.isQuiet(TimeOfDay(hour: 8)))
        #expect(!p.isQuiet(TimeOfDay(hour: 14, minute: 30)))
    }

    @Test("Goal target date follows the horizon")
    func goalTarget() {
        let goal = WowFixture.goals[0]
        let target = goal.targetDate(calendar: WowFixture.calendar)
        #expect(target == WowFixture.calendar.startOfDay(for: WowFixture.moment(0, 0, dayOffset: 4)))  // Mon 7 → Sun 13
    }
}
