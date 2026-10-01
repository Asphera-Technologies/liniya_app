import Testing
import Foundation
@testable import LineaCore

/// Строка + чипы → задача. Время — среда 9 сентября 2026, 08:00 по Москве.
@Suite("Быстрый ввод: черновик и чипы")
struct QuickTaskDraftTests {
    private let time = WowFixture.morning

    private func resolve(
        _ draft: QuickTaskDraft,
        at time: TimeContext? = nil,
        goals: [LineaGoal] = WowFixture.goals,
        linker: GoalLinker = GoalLinker()
    ) -> QuickTaskResolution {
        draft.resolve(goals: goals, profile: WowFixture.profile, time: time ?? self.time, linker: linker)
    }

    @Test("Одно название — задача на сегодня, средний приоритет, остальное Linea решит сама")
    func titleOnly() {
        let result = resolve(QuickTaskDraft(text: "Оплатить интернет"))
        #expect(result.canSave)
        #expect(result.title == "Оплатить интернет")
        #expect(result.date == WowFixture.today)
        #expect(result.dayOrigin == .assumed)
        #expect(result.priority == .normal)
        #expect(result.priorityOrigin == .assumed)
        #expect(result.minutes == nil)
        #expect(result.goalID == nil)
        #expect(result.suggestion == nil)

        let task = result.task(id: WowFixture.taskA, createdAt: time.now)
        #expect(task.id == WowFixture.taskA)
        #expect(task.title == "Оплатить интернет")
        #expect(task.date == WowFixture.today)
        #expect(task.estimatedMinutes == nil)
        #expect(task.isDone == false)
    }

    @Test("Пустая строка не сохраняется")
    func emptyTitle() {
        #expect(resolve(QuickTaskDraft(text: "   ")).canSave == false)
    }

    @Test("Чип сильнее сказанного: день, приоритет, длительность")
    func chipsOverrideText() {
        var draft = QuickTaskDraft(text: "Отчёт сегодня срочно на час")
        draft.day = .tomorrow
        draft.priority = .low
        draft.minutes = 15
        let result = resolve(draft)
        #expect(result.title == "Отчёт")
        #expect(result.date == WowFixture.calendar.startOfDay(for: WowFixture.moment(12, 0, dayOffset: 1)))
        #expect(result.dayOrigin == .chosen)
        #expect(result.priority == .low)
        #expect(result.priorityOrigin == .chosen)
        #expect(result.minutes == 15)
        #expect(result.minutesOrigin == .chosen)

        let typed = resolve(QuickTaskDraft(text: "Отчёт сегодня срочно на час"))
        #expect(typed.dayOrigin == .typed)
        #expect(typed.priority == .important)
        #expect(typed.priorityOrigin == .typed)
        #expect(typed.minutes == 60)
    }

    @Test("Время начала живёт на дне задачи: сменили день — время переехало")
    func startMovesWithDay() {
        var draft = QuickTaskDraft(text: "Созвон в 15:00")
        #expect(resolve(draft).scheduledStart == WowFixture.moment(15))
        draft.day = .tomorrow
        #expect(resolve(draft).scheduledStart == WowFixture.moment(15, 0, dayOffset: 1))
        // Время уже прошло — значит, завтра.
        let late = resolve(QuickTaskDraft(text: "Позвонить в 10:00"), at: WowFixture.time(20))
        #expect(late.day == .tomorrow)
        #expect(late.scheduledStart == WowFixture.moment(10, 0, dayOffset: 1))
    }

    @Test("«На неделе» — без дня, срок в воскресенье")
    func thisWeek() {
        var draft = QuickTaskDraft(text: "Подготовить релиз")
        draft.day = .thisWeek
        let result = resolve(draft)
        #expect(result.date == nil)
        #expect(result.deadline == WowFixture.moment(21, 0, dayOffset: 4))
        #expect(result.deadlineOrigin == .chosen)
        #expect(QuickTaskText.day(result, time: time) == "На неделе")
    }

    @Test("Срок без дня — задача без дня; день из чипа остаётся вместе со сроком")
    func deadlineWithoutDay() {
        var draft = QuickTaskDraft(text: "Отчёт к пятнице")
        let typed = resolve(draft)
        #expect(typed.date == nil)
        #expect(typed.deadline == WowFixture.moment(21, 0, dayOffset: 2))
        draft.day = .today
        let both = resolve(draft)
        #expect(both.date == WowFixture.today)
        #expect(both.deadline == WowFixture.moment(21, 0, dayOffset: 2))

        var chosen = QuickTaskDraft(text: "Отчёт")
        chosen.deadline = .at(WowFixture.moment(18, 0, dayOffset: 1))
        let picked = resolve(chosen)
        #expect(picked.date == nil)
        #expect(picked.deadline == WowFixture.moment(18, 0, dayOffset: 1))
        #expect(picked.deadlineOrigin == .chosen)

        #expect(resolve(QuickTaskDraft(text: "Отчёт к пятнице", deadline: .noDeadline)).deadline == nil)
    }

    @Test("Цель: подсказка по словам, явная «для цели …», «Без цели» сильнее всего")
    func goals() {
        let hint = resolve(QuickTaskDraft(text: "Запустить лендинг"))
        #expect(hint.goalID == nil)
        #expect(hint.suggestion?.goalID == WowFixture.goalMVP)
        #expect(hint.suggestion?.source == .suggested)

        let explicit = resolve(QuickTaskDraft(text: "Подготовить релиз для цели MVP"))
        #expect(explicit.goalID == WowFixture.goalMVP)
        #expect(explicit.goalOrigin == .typed)
        #expect(explicit.suggestion == nil)

        var cleared = QuickTaskDraft(text: "Подготовить релиз для цели MVP")
        cleared.goal = .noGoal
        let none = resolve(cleared)
        #expect(none.goalID == nil)
        #expect(none.suggestion == nil)

        var picked = QuickTaskDraft(text: "Купить продукты")
        picked.goal = .linked(WowFixture.goalMVP)
        #expect(resolve(picked).goalID == WowFixture.goalMVP)
        #expect(resolve(picked).goalOrigin == .chosen)
    }

    @Test("Автосвязь заложена: по политике уверенное совпадение связывается само")
    func automaticLink() {
        let automatic = GoalLinker(policy: .automatic(minimumScore: 0.3))
        let result = resolve(QuickTaskDraft(text: "Запустить лендинг"), linker: automatic)
        #expect(result.goalID == WowFixture.goalMVP)
        #expect(result.goalOrigin == .assumed)
        #expect(result.suggestion == nil)
        // По умолчанию — только подсказка.
        #expect(GoalLinker.defaultPolicy == .suggestOnly)
        // Завершённая цель не предлагается.
        var done = WowFixture.goals[0]
        done.isCompleted = true
        #expect(resolve(QuickTaskDraft(text: "Запустить лендинг"), goals: [done]).suggestion == nil)
    }

    @Test("Подписи чипов: дни, время, срок, длительность")
    func labels() {
        func label(_ text: String, day: TaskDay? = nil) -> String {
            QuickTaskText.day(resolve(QuickTaskDraft(text: text, day: day)), time: time)
        }
        #expect(label("Отчёт") == "Сегодня")
        #expect(label("Отчёт завтра в 15:00") == "Завтра, 15:00")
        #expect(label("Отчёт в пятницу") == "Пт, 11 сен")
        #expect(label("Отчёт до 18:00") == "до 18:00")
        #expect(label("Отчёт к пятнице") == "до пт, 11 сен")
        #expect(label("Отчёт сегодня до 18:00") == "Сегодня, до 18:00")
        #expect(label("Отчёт когда-нибудь") == "Без даты")
        #expect(label("Отчёт", day: .someday) == "Без даты")
        #expect(label("Подарок 1 сентября") == "Ср, 1 сен 2027")

        #expect(QuickTaskText.duration(minutes: 30) == "~30 мин")
        #expect(QuickTaskText.duration(minutes: 60) == "~1 ч")
        #expect(QuickTaskText.duration(minutes: 90) == "~1 ч 30 мин")
    }
}
