import Foundation
import Testing
@testable import LineaCore

struct TaskTimerTests {
    @Test func persistedSessionRemainsPausedAndTracksOnlyWorkedTime() throws {
        let start = WowFixture.moment(10)
        let original = LineaTask(title: "Презентация", estimatedMinutes: 45)
        let output = try #require(TaskExecutionUseCase().run(.start, task: original, record: nil,
                                                           plannedMinutes: 30, at: start))
        var task = output.task
        task.timer?.setPaused(true, at: WowFixture.moment(10, 5))
        task = try JSONDecoder().decode(LineaTask.self, from: JSONEncoder().encode(task))
        #expect(task.timer?.remainingSeconds(at: WowFixture.moment(10, 15)) == 25 * 60)
        task.timer?.setPaused(false, at: WowFixture.moment(10, 15))
        #expect(task.timer?.remainingSeconds(at: WowFixture.moment(10, 20)) == 20 * 60)
        #expect(task.timer?.remainingSeconds(at: WowFixture.moment(10, 50)) == 0)
        #expect(task.isOpen)
        let finished = try #require(TaskLifecycle().finish(task, suggestionID: nil, at: WowFixture.moment(10, 20)))
        #expect(finished.actualMinutes == 10)
        #expect(finished.timer == nil)
    }
}
