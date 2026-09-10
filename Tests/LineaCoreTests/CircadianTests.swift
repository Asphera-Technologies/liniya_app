import Testing
import Foundation
@testable import LineaCore

@Suite("Circadian")
struct CircadianTests {
    @Test("Peaks at 11:00, dips after lunch, flat outside the nodes")
    func shape() {
        #expect(Circadian.alertness(atHour: 11) == 1.0)
        #expect(abs(Circadian.alertness(atHour: 14) - 0.65) < 1e-9)
        #expect(abs(Circadian.alertness(atHour: 9.5) - 0.90) < 1e-9)   // between 0.85 and 0.95
        #expect(Circadian.alertness(atHour: 3) == 0.45)
        #expect(Circadian.alertness(atHour: 23.9) == 0.30)
    }

    @Test("Capacity scales with energy but keeps half the curve")
    func capacity() {
        let t = WowFixture.morning
        let at10 = WowFixture.moment(10)
        #expect(abs(Circadian.capacity(energy: 1, at: at10, time: t) - 0.95) < 1e-9)
        #expect(abs(Circadian.capacity(energy: 0, at: at10, time: t) - 0.475) < 1e-9)
        #expect(abs(Circadian.capacity(energy: 0.4, at: at10, time: t) - 0.665) < 1e-9)
    }
}
