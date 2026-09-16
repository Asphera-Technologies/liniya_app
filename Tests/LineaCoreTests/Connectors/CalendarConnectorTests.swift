import Testing
import Foundation
@testable import LineaCore

@Suite("Коннектор календаря")
struct CalendarConnectorTests {
    private let mapper = CalendarSignalMapper()
    private let time = WowFixture.morning
    private var day: DateInterval { time.dayInterval(containing: time.today) }

    private func event(
        _ title: String,
        _ from: (Int, Int),
        _ to: (Int, Int),
        id: String = "e1",
        allDay: Bool = false,
        busy: Bool = true,
        canceled: Bool = false
    ) -> CalendarEvent {
        CalendarEvent(
            id: id, title: title,
            start: WowFixture.moment(from.0, from.1),
            end: WowFixture.moment(to.0, to.1),
            isAllDay: allDay, isBusy: busy, isCanceled: canceled,
            calendarTitle: "Работа"
        )
    }

    @Test("Встреча становится занятым временем")
    func meetingBecomesCommitment() throws {
        let signals = mapper.signals(from: [event("Планёрка", (11, 0), (11, 30))], in: day, source: .calendar)
        let signal = try #require(signals.first)
        #expect(signal.kind == .commitment)
        #expect(signal.start == WowFixture.moment(11))
        #expect(signal.end == WowFixture.moment(11, 30))
        #expect(signal.attributes[SignalAttribute.label] == "Планёрка")
        #expect(signal.attributes[SignalAttribute.commitmentKind] == CommitmentKind.meeting.rawValue)
        #expect(signal.attributes[SignalAttribute.eventID] == "e1")
        #expect(signal.attributes["calendar"] == "Работа")
    }

    @Test("Тренировка в календаре узнаётся по названию")
    func workoutIsRecognised() throws {
        let signals = mapper.signals(from: [event("Тренировка в зале", (17, 0), (18, 0))], in: day, source: .calendar)
        #expect(signals.first?.attributes[SignalAttribute.commitmentKind] == CommitmentKind.workout.rawValue)
    }

    @Test("День рождения и отпуск не съедают день")
    func allDayEventsAreIgnored() {
        let birthday = CalendarEvent(id: "b", title: "День рождения", start: day.start, end: day.end, isAllDay: true)
        #expect(mapper.signals(from: [birthday], in: day, source: .calendar).isEmpty)
    }

    @Test("Событие со статусом «свободен» не занимает время")
    func freeEventsAreIgnored() {
        #expect(mapper.blockingEvents([event("Напоминание", (11, 0), (12, 0), busy: false)], in: day).isEmpty)
    }

    @Test("Отменённая встреча не занимает время")
    func canceledEventsAreIgnored() {
        #expect(mapper.blockingEvents([event("Отменено", (11, 0), (12, 0), canceled: true)], in: day).isEmpty)
    }

    @Test("Пятиминутные пометки не дробят день")
    func tinyEventsAreIgnored() {
        #expect(mapper.blockingEvents([event("Позвонить", (11, 0), (11, 5))], in: day).isEmpty)
        #expect(mapper.blockingEvents([event("Созвон", (11, 0), (11, 30))], in: day).count == 1)
    }

    @Test("Многодневная поездка не вычитается целиком")
    func veryLongEventsAreIgnored() {
        let trip = CalendarEvent(
            id: "t", title: "Командировка",
            start: WowFixture.moment(8), end: WowFixture.moment(8, 0, dayOffset: 2)
        )
        #expect(mapper.blockingEvents([trip], in: day).isEmpty)
    }

    @Test("События вне дня отбрасываются, пересекающие — остаются")
    func windowFiltering() {
        let yesterday = event("Вчера", (10, 0), (11, 0), id: "y")
        let shifted = CalendarEvent(
            id: "y2", title: "Вчера",
            start: WowFixture.moment(10, 0, dayOffset: -1),
            end: WowFixture.moment(11, 0, dayOffset: -1)
        )
        #expect(mapper.blockingEvents([shifted], in: day).isEmpty)
        #expect(mapper.blockingEvents([yesterday], in: day).count == 1)
    }

    @Test("Порядок событий детерминирован")
    func deterministicOrder() {
        let a = event("Б", (12, 0), (13, 0), id: "b")
        let b = event("А", (11, 0), (12, 0), id: "a")
        let ordered = mapper.blockingEvents([a, b], in: day).map(\.id)
        #expect(ordered == ["a", "b"])
        #expect(mapper.blockingEvents([b, a], in: day).map(\.id) == ordered)
    }

    @Test("Те же события отдаются обязательствами для экрана «План»")
    func commitmentsForTheScreen() throws {
        let events = [
            event("Планёрка", (10, 0), (11, 0), id: "a"),
            event("Тренировка", (17, 0), (18, 0), id: "b"),
            event("День рождения", (0, 0), (23, 59), id: "c", allDay: true),
        ]
        let commitments = mapper.commitments(from: events, in: day, source: .calendar)
        #expect(commitments.count == 2)
        #expect(commitments.first?.title == "Планёрка")
        #expect(commitments.first?.kind == .meeting)
        #expect(commitments.last?.kind == .workout)
        #expect(commitments.allSatisfy { $0.source == .calendar })
        // Идентификаторы стабильны: строка не «прыгает» при обновлении экрана.
        #expect(commitments.first?.id == "calendar-a")
    }

    @Test("Событие календаря доходит до плана и вычитается из свободного времени")
    func calendarShapesTheDay() async throws {
        let meeting = event("Планёрка", (10, 0), (11, 30), id: "planning")
        let signals = mapper.signals(from: [meeting], in: day, source: .calendar)

        let engine = ContextEngine(providers: [
            FakeContextProvider(id: .calendar, signals: signals),
        ])
        let snapshot = await engine.capture(
            request: ContextRequest(day: day, time: time),
            snapshotID: WowFixture.snapshotID,
            tasks: WowFixture.tasks, goals: WowFixture.goals,
            profile: WowFixture.profile, nutrition: nil, meals: []
        )
        // Ядро не знает про календарь: событие пришло обычным обязательством.
        let commitment = try #require(snapshot.commitments.first { $0.title == "Планёрка" })
        #expect(commitment.kind == .meeting)
        #expect(commitment.source == .calendar)

        let plan = DecisionEngine(rules: [], renderer: StubRenderer())
            .plan(snapshot: snapshot, state: PlanFixture.reducedState(at: time), time: time, planID: WowFixture.planID)
        // Ни один рабочий блок не залезает на встречу.
        for block in plan.focusBlocks {
            #expect(block.end <= commitment.start || block.start >= commitment.end)
        }
        #expect(plan.blocks.contains { $0.title == "Планёрка" && $0.kind == .commitment })
    }
}
