import Foundation
import Testing
@testable import LineaCore

struct VoiceTaskWindowTests {
    private let time = WowFixture.time(8)

    @Test func reminderIsNotMeetingDuration() {
        let text = "Завтра в 10:00 у меня совещание, напомни мне за 30 минут."
        let result = QuickTaskDraft(text: text).resolve(goals: [], profile: .default, time: time)
        #expect(result.title == "Совещание")
        #expect(result.day == .tomorrow)
        #expect(result.scheduledStart == WowFixture.moment(10, dayOffset: 1))
        #expect(result.reminderLeadMinutes == 30)
        #expect(result.minutes == nil)
        #expect(VoiceTaskWindow.isEventCommand(text))
    }

    @Test func separateDurationAndReminder() {
        let text = "Добавь задачу завтра в 15:00 подготовить отчет на час, напомни за 20 минут"
        let result = QuickTaskDraft(text: text).resolve(goals: [], profile: .default, time: time)
        #expect(result.title == "Подготовить отчет")
        #expect(result.minutes == 60)
        #expect(result.reminderLeadMinutes == 20)
        #expect(!VoiceTaskWindow.isEventCommand(text))
        let hours = QuickTaskParser().parse("Встреча завтра в 15:00, напомни за полчаса", time: time)
        #expect(hours.reminderLeadMinutes == 30)
        #expect(hours.minutes == nil)
        let noReminder = QuickTaskParser().parse("Подготовить напоминание за 30 минут", time: time)
        #expect(noReminder.reminderLeadMinutes == nil)
        #expect(noReminder.minutes == 30)
    }

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
