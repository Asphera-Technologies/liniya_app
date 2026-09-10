import Testing
import Foundation
@testable import LineaCore

@Suite("Core smoke")
struct CoreSmokeTests {
    @Test("Domain models compile in the Foundation-only core")
    func domainModelsAreAvailable() {
        let task = LineaTask(title: "Презентация КП")
        let goal = LineaGoal(title: "Запустить MVP Linea")
        #expect(task.isDone == false)
        #expect(goal.progress == 0)
    }
}
