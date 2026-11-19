import Foundation
import Testing
@testable import LineaCore

struct VoiceTaskWindowTests {
    private let time = WowFixture.time(8)

    @Test func spokenTimeAndDuration() throws {
        let parser = QuickTaskParser()
        let event = parser.parse("Запиши, завтра в 20:00 парикмахер", time: time)
        #expect(VoiceTaskWindow.isEventCommand("Запиши, завтра в 20:00 парикмахер"))
        #expect(!VoiceTaskWindow.isEventCommand("Добавь задачу завтра в 20:00"))
        #expect(event.title == "Парикмахер")
        #expect(event.day == .tomorrow)
        #expect(event.startTime == TimeOfDay(hour: 20))
        let ambiguous = parser.parse("Парикмахер завтра в 7 часов", time: time, requiresExplicitStart: true)
        #expect(ambiguous.startTime == nil)
        #expect(ambiguous.minutes == nil)
        let explicit = parser.parse("Парикмахер завтра в 7 вечера", time: time, requiresExplicitStart: true)
        #expect(explicit.startTime == TimeOfDay(hour: 19))
        let task = parser.parse("Завтра нужно сделать презентацию, займёт часа три", time: time)
        #expect(task.minutes == 180)
        #expect(task.startTime == nil)
    }

    @Test func fitsAroundMeetingAndPlanBlock() throws {
        let day = time.today
        let meeting = Commitment(id: "meeting", title: "Встреча", start: WowFixture.moment(9),
                                 end: WowFixture.moment(12), kind: .meeting, source: .calendar)
        let block = PlanBlock(id: "report", kind: .focus, title: "Отчет", start: WowFixture.moment(12),
                              end: WowFixture.moment(14))
        let plan = DayPlan(id: UUID(), day: day, createdAt: time.now, snapshotID: UUID(), blocks: [block], topTaskIDs: [])
        let context = RescheduleContext(profile: .default, tasks: [], commitments: [meeting], time: time)
        let slot = try #require(VoiceTaskWindow.find(minutes: 180, day: day, deadline: nil, context: context, plan: plan))
        #expect(slot.start == WowFixture.moment(14))
        #expect(slot.end == WowFixture.moment(17))
    }

    @Test func twoSmallerWindowsDoNotCountAsOne() {
        let profile = UserProfile(workdayEnd: TimeOfDay(hour: 16))
        let fixed = LineaTask(title: "Занято", date: time.today, scheduledStart: WowFixture.moment(11),
                              estimatedMinutes: 180)
        let context = RescheduleContext(profile: profile, tasks: [fixed], time: time)
        #expect(VoiceTaskWindow.find(minutes: 180, day: time.today, deadline: nil, context: context, plan: nil) == nil)
    }
}
