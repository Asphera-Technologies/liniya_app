import Testing
import Foundation
@testable import LineaCore

/// «Перенести» у строки задачи. Время — среда 9 сентября 2026, 08:00 по Москве:
/// завтра — четверг 10-е, конец недели — воскресенье 13-е, следующая неделя —
/// понедельник 14-е.
@Suite("Перенести задачу")
struct TaskRescheduleTests {
    private let time = WowFixture.morning
    private let reschedule = TaskReschedule()
    private var profile: UserProfile { WowFixture.profile }

    private func day(_ offset: Int) -> Date { time.adding(days: offset, to: WowFixture.today) }

    private func task(
        date: Date? = nil,
        deadline: Date? = nil,
        start: Date? = nil,
        isDone: Bool = false
    ) -> LineaTask {
        LineaTask(id: UUID(uuidString: "71000000-0000-0000-0000-000000000001")!, title: "Позвонить маме",
                  date: date, isDone: isDone, createdAt: WowFixture.created, deadline: deadline, scheduledStart: start)
    }

    private func titles(_ task: LineaTask, at time: TimeContext? = nil) -> [String] {
        reschedule.options(for: task, profile: profile, time: time ?? self.time).map(\.title)
    }

    // MARK: Варианты

    @Test("Задача на сегодня: завтра, на неделе, следующая неделя, без даты — «Сегодня» не предлагается")
    func optionsForToday() {
        #expect(titles(task(date: WowFixture.today)) == [
            "Завтра", "На неделе · до вс, 13 сен", "На следующей неделе · пн, 14 сен", "Без даты",
        ])
    }

    @Test("Без даты — можно дать день; просроченную — вернуть в сегодня; закрытую не переносят")
    func optionsForOtherTasks() {
        #expect(titles(task()) == ["Сегодня", "Завтра", "На неделе · до вс, 13 сен", "На следующей неделе · пн, 14 сен"])
        #expect(titles(task(date: day(-1))).first == "Сегодня")
        #expect(titles(task(date: day(1))) == ["Сегодня", "На неделе · до вс, 13 сен", "На следующей неделе · пн, 14 сен", "Без даты"])
        let thisWeek = task(deadline: TaskDay.endOfWeek(time: time, profile: profile))
        #expect(titles(thisWeek) == ["Сегодня", "Завтра", "На следующей неделе · пн, 14 сен", "Без даты"])
        #expect(titles(task(date: WowFixture.today, isDone: true)).isEmpty)
    }

    @Test("В воскресенье следующая неделя — это завтра: отдельного пункта нет")
    func sundayHasNoSeparateNextWeek() {
        let sunday = WowFixture.time(10, dayOffset: 4)
        let options = titles(task(date: sunday.today), at: sunday)
        #expect(options.contains("Завтра"))
        #expect(!options.contains { $0.hasPrefix("На следующей неделе") })
    }

    // MARK: Что станет с задачей

    @Test("Завтра: время и срок дня переезжают на тот же час")
    func movesTimeAndSameDayDeadline() {
        let original = task(date: WowFixture.today, deadline: WowFixture.moment(18), start: WowFixture.moment(15))
        let moved = reschedule.apply(.tomorrow, to: original, profile: profile, time: time)
        #expect(moved.date == day(1))
        #expect(moved.scheduledStart == WowFixture.moment(15, 0, dayOffset: 1))
        #expect(moved.deadline == WowFixture.moment(18, 0, dayOffset: 1))
        #expect(moved.title == original.title)
        #expect(moved.isDone == false)
    }

    @Test("Срок, который ещё впереди, остаётся; срок, который остался бы позади, — переезжает")
    func deadlineAheadStays() {
        let friday = WowFixture.moment(18, 0, dayOffset: 2)
        let dueFriday = task(date: WowFixture.today, deadline: friday)
        #expect(reschedule.apply(.tomorrow, to: dueFriday, profile: profile, time: time).deadline == friday)
        let nextWeek = reschedule.apply(.nextWeek, to: dueFriday, profile: profile, time: time)
        #expect(nextWeek.date == day(5))
        #expect(nextWeek.deadline == WowFixture.moment(18, 0, dayOffset: 5))

        // «На неделе» без дня — срок воскресенья остаётся и при дне.
        let thisWeek = task(deadline: TaskDay.endOfWeek(time: time, profile: profile))
        let thursday = reschedule.apply(.tomorrow, to: thisWeek, profile: profile, time: time)
        #expect(thursday.date == day(1))
        #expect(thursday.deadline == TaskDay.endOfWeek(time: time, profile: profile))
    }

    @Test("Просроченная — в сегодня вместе со своим сроком; свой день из календаря")
    func overdueAndCustomDay() {
        let overdue = task(date: day(-1), deadline: WowFixture.moment(18, 0, dayOffset: -1))
        let today = reschedule.apply(.today, to: overdue, profile: profile, time: time)
        #expect(today.date == WowFixture.today)
        #expect(today.deadline == WowFixture.moment(18))

        let picked = reschedule.apply(.day(WowFixture.moment(13, 30, dayOffset: 9)), to: task(date: WowFixture.today),
                                      profile: profile, time: time)
        #expect(picked.date == day(9))
    }

    @Test("На неделе: без дня и своего времени, срок — конец недели, если свой не раньше")
    func thisWeek() {
        let endOfWeek = TaskDay.endOfWeek(time: time, profile: profile)
        let today = task(date: WowFixture.today, deadline: WowFixture.moment(18), start: WowFixture.moment(15))
        let moved = reschedule.apply(.thisWeek, to: today, profile: profile, time: time)
        #expect(moved.date == nil)
        #expect(moved.scheduledStart == nil)
        #expect(moved.deadline == endOfWeek)

        let friday = WowFixture.moment(18, 0, dayOffset: 2)
        let dueFriday = reschedule.apply(.thisWeek, to: task(date: WowFixture.today, deadline: friday), profile: profile, time: time)
        #expect(dueFriday.deadline == friday)
    }

    @Test("Без даты — во входящие, уже разобранной; из входящих — с днём и тоже разобранной")
    func somedayAndInbox() {
        let someday = reschedule.apply(.someday, to: task(date: WowFixture.today, deadline: WowFixture.moment(18),
                                                          start: WowFixture.moment(15)),
                                       profile: profile, time: time)
        #expect(InboxReview.isInInbox(someday))
        #expect(someday.inboxReviewedAt == time.now)
        #expect(InboxReview.unsorted([someday]).isEmpty)

        let scheduled = reschedule.apply(.tomorrow, to: task(), profile: profile, time: time)
        #expect(scheduled.date == day(1))
        #expect(scheduled.deadline == nil)
        #expect(scheduled.inboxReviewedAt == time.now)
    }

    @Test("Перенос задачи, которую пора было делать, — это перенос: счётчик растёт")
    func countsAsDeferral() {
        let today = task(date: WowFixture.today)
        let moved = reschedule.apply(.tomorrow, to: today, profile: profile, time: time)
        #expect(TaskDeferral.counted(previous: today, updated: moved, time: time).deferralCount == 1)
        let fromInbox = reschedule.apply(.tomorrow, to: task(), profile: profile, time: time)
        #expect(TaskDeferral.counted(previous: task(), updated: fromInbox, time: time).deferralCount == 0)
    }
}
