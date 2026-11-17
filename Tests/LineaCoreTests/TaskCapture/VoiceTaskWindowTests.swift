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
}
