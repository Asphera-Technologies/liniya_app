import Testing
import Foundation
@testable import LineaCore

/// Цели команды и компании: общий прогресс и вклад человека — разные вещи,
/// шаги — только в его части. Время — среда 9 сентября 2026, 08:00 по Москве.
@Suite("Цели команды и компании")
struct TeamGoalTests {
    private let time = WowFixture.morning
    private let profile = WowFixture.profile
    private let goalID = UUID(uuidString: "60C10000-0000-0000-0000-000000000001")!
    private let part = "Новые enterprise-клиенты и ключевые переговоры"

    private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "60C20000-0000-0000-0000-%012d", n))! }

    /// Пример заказчика: «Достичь 5 млн ₽ выручки / месяц», scope = company.
    private var revenue: LineaGoal {
        LineaGoal(
            id: goalID, title: "Довести выручку компании до 5 млн ₽ в месяц", createdAt: WowFixture.created,
            metrics: [GoalMetric(id: id(1), unit: "₽", current: 3_200_000, target: 5_000_000)],
            progressMethod: .metric,
            scope: .company,
            ownerScope: part,
            contributionMetrics: [GoalMetric(id: id(2), unit: "enterprise-клиентов", current: 2, target: 5)]
        )
    }

    private func myTasks(closed: Int, open: Int) -> [LineaTask] {
        (0..<closed).map { n in
            LineaTask(id: id(10 + n), title: "Переговоры \(n)", isDone: true, createdAt: WowFixture.created,
                      goalID: goalID, completedAt: WowFixture.moment(18, dayOffset: -(n + 1)))
        } + (0..<open).map { n in
            LineaTask(id: id(30 + n), title: "Встреча \(n)", createdAt: WowFixture.created, goalID: goalID)
        }
    }

    // MARK: Создание

    @Test("Пример заказчика одной строкой: цель компании, сумма — число цели, часть человека — своими словами")
    func quickCompanyGoal() {
        var draft = QuickGoalDraft(text: "Довести выручку компании до 5 млн ₽ в месяц")
        let guessed = draft.resolve(profile: profile, time: time)
        #expect(guessed.understanding.scope == .company)
        #expect(guessed.scopeOrigin == .typed, "Компанию Linea увидела в словах")
        #expect(guessed.title == "Довести выручку компании до 5 млн ₽ в месяц")
        #expect(guessed.understanding.metrics.first.map(GoalProgressText.metric) == "0 из 5 млн ₽")
        #expect(guessed.understanding.method == .metric)
        #expect(QuickGoalText.summary(guessed, time: time) == "цель компании")

        draft.ownerScope = part
        let goal = draft.resolve(profile: profile, time: time).goal(id: goalID, createdAt: time.now, time: time)
        #expect(goal.scope == .company)
        #expect(goal.ownerScope == part)
        #expect(goal.ownPart == part)
    }

    @Test("«От меня» сильнее слов: цель своя, части и вопроса о ней нет")
    func personalChoiceWins() {
        var draft = QuickGoalDraft(text: "Довести выручку компании до 5 млн ₽ в месяц", scope: .personal)
        draft.ownerScope = "что-то"
        let resolution = draft.resolve(profile: profile, time: time)
        #expect(resolution.understanding.scope == .personal)
        #expect(resolution.scopeOrigin == .chosen)
        #expect(resolution.understanding.ownerScope == nil)
        #expect(resolution.understanding.question != .owner)
        #expect(resolution.goal(id: goalID, createdAt: time.now, time: time).ownerScope == nil)
    }

    @Test("Подробно: у общей цели первый вопрос — за какую часть отвечаешь ты; ответ — owner_scope")
    func ownerQuestionFirst() {
        let analyzer = RuleBasedGoalAnalyzer()
        var input = GoalIntakeInput(title: "Довести выручку компании до 5 млн ₽ в месяц")
        let first = analyzer.understand(input, profile: profile, time: time)
        #expect(first.question == .owner)
        #expect(first.question?.text == "За какую часть этой цели отвечаешь ты?")

        input.answers[.owner] = "привлечение крупных клиентов и ключевые переговоры"
        let answered = analyzer.understand(input, profile: profile, time: time)
        #expect(answered.ownerScope == "Привлечение крупных клиентов и ключевые переговоры")
        #expect(answered.question != .owner)
        #expect(answered.targetState == "Довести выручку компании до 5 млн ₽ в месяц.", "Ответ о части — не результат цели")

        var skipped = GoalIntakeInput(title: "Довести выручку компании до 5 млн ₽ в месяц", skipped: [.owner])
        #expect(analyzer.understand(skipped, profile: profile, time: time).question != .owner)
        skipped.scope = .personal
        #expect(analyzer.understand(skipped, profile: profile, time: time).ownerScope == nil)
    }

    // MARK: Прогресс и вклад

    @Test("Общий прогресс и вклад — отдельно: 4 из 5 своих задач не делают цель компании на 80%")
    func progressAndContributionApart() throws {
        let progress = GoalProgressEngine().progress(of: revenue, tasks: myTasks(closed: 4, open: 1), time: time)
        #expect(progress.value == 0.64, "Общий прогресс — по выручке, которую знает человек")
        #expect(GoalProgressText.summary(progress, time: time) == "3,2 млн из 5 млн ₽ · 64%")
        #expect(progress.recentActions == 0, "Свои задачи — не движение общей цели")

        let contribution = try #require(progress.contribution)
        #expect(contribution.part == part)
        #expect(contribution.value == 0.4)
        #expect(contribution.closedTasks == 4)
        #expect(contribution.openTasks == 1)
        #expect(contribution.recentActions == 4)
        #expect(contribution.lastActionAt == WowFixture.moment(18, dayOffset: -1))
        #expect(GoalProgressText.contributionSummary(contribution, time: time) == "Моя часть: 2 из 5 enterprise-клиентов · 40%")
        #expect(GoalProgressText.scopeLabel(.company) == "Компания")
        #expect(GoalProgressText.scopeLabel(.personal) == nil)

        // Без общего числа общего процента нет — и задачи его не создают.
        var unknown = revenue
        unknown.metrics = []
        unknown.contributionMetrics = []
        let blind = GoalProgressEngine().progress(of: unknown, tasks: myTasks(closed: 4, open: 1), time: time)
        #expect(blind.value == nil)
        let own = try #require(blind.contribution)
        #expect(own.value == nil, "Без своего числа процента вклада тоже нет")
        #expect(GoalProgressText.contributionSummary(own, time: time) == "Моя часть: 4 действия за 30 дней")
        let lines = GoalProgressText.contributionLines(own, time: time)
        #expect(lines.map(\.value) == ["4 закрыто · 1 открыто", "вчера", "4 действия"])
        let fresh = GoalProgressEngine().progress(of: unknown, tasks: [], time: time)
        let empty = try #require(fresh.contribution)
        #expect(GoalProgressText.contributionLines(empty, time: time).map(\.value)
                == ["пока нет", "пока не было", "ни одного действия"])
        let openOnly = try #require(GoalProgressEngine().progress(of: unknown, tasks: myTasks(closed: 0, open: 2), time: time).contribution)
        #expect(GoalProgressText.contributionLines(openOnly, time: time).first?.value == "2 открыто")
    }

    @Test("У своей цели задачи — значимые действия цели, вклада отдельно нет")
    func personalGoalHasNoContribution() {
        var mine = revenue
        mine.scope = .personal
        let progress = GoalProgressEngine().progress(of: mine, tasks: myTasks(closed: 2, open: 0), time: time)
        #expect(progress.contribution == nil)
        #expect(progress.recentActions == 2)
        #expect(mine.ownPart == nil, "Часть бывает только у общей цели")
    }

    @Test("Своё число ближе к цели — вклад, а не продвижение общей цели")
    func contributionEvents() {
        var updated = revenue
        updated.contributionMetrics[0].current = 3
        let saved = GoalRevision.saved(previous: revenue, updated: updated, time: time)
        #expect(saved.progressLog.map(\.kind) == [.contributionUpdated])
        #expect(saved.progressLog.first?.detail == "3 enterprise-клиентов")
        #expect(saved.contributionMetrics[0].updatedAt == time.now)

        var qualitative = saved
        qualitative.progressMethod = .qualitative
        let progress = GoalProgressEngine().progress(of: qualitative, tasks: [], time: time)
        #expect(progress.lastProgressAt == nil, "Вклад не двигает общую цель")
        #expect(progress.contribution?.lastActionAt == time.now)
    }

    // MARK: Шаги — только в своей части

    @Test("Шаги и окна — в части человека, а не во всей работе компании")
    func stepScopeIsOwnPart() {
        let scope = GoalStepScope.of(revenue)
        #expect(scope.isOwnPart)
        #expect(scope.windowTitle == "Окно для своей части: \(part)")
        #expect(scope.decompositionBrief.hasPrefix("Моя часть: \(part)."))
        #expect(scope.decompositionBrief.contains("не моя работа целиком"))

        var noPart = revenue
        noPart.ownerScope = nil
        #expect(GoalStepScope.of(noPart).windowTitle == "Окно для цели «Довести выручку компании до 5 млн ₽ в месяц»")
        let personal = LineaGoal(title: "Запустить Линия Beta", createdAt: WowFixture.created)
        #expect(GoalStepScope.of(personal).windowTitle == "Окно для цели «Запустить Линия Beta»")
        #expect(GoalStepScope.of(personal).decompositionBrief == "Запустить Линия Beta")
    }

    @Test("Задачу к общей цели Linea узнаёт по части человека")
    func matchingByOwnPart() {
        let matcher = ConceptGoalMatcher()
        #expect(matcher.bestMatch(for: "Встреча с enterprise-клиентом", in: [revenue])?.goalID == goalID)
        var noPart = revenue
        noPart.ownerScope = nil
        #expect(matcher.bestMatch(for: "Встреча с enterprise-клиентом", in: [noPart]) == nil)
    }

    @Test("«От меня», а потом снова «От команды» — цель опять компании, а не просто команды (баг тестировщика)")
    func sharedKindIsRemembered() throws {
        var goal = revenue
        goal.setShared(false)
        #expect(goal.scope == .personal)
        #expect(goal.ownerScope == part, "Своя часть остаётся, как и раньше")
        #expect(goal.sharedScope == .company, "Какой общей цель была — помнится")

        // Сохранили своей и открыли снова — память переживает сохранение.
        let stored = try JSONDecoder().decode(LineaGoal.self, from: JSONEncoder().encode(goal))
        #expect(stored.scope == .personal)
        #expect(stored.sharedScope == .company)
        var reopened = stored
        reopened.setShared(true)
        #expect(reopened.scope == .company)
        #expect(GoalProgressText.scopeLabel(reopened.scope) == "Компания", "В «Плане» — «Компания · …»")

        // Своя цель, впервые ставшая общей, — команды; выбор «Вся компания» помнится.
        var own = LineaGoal(title: "Сделать ремонт", createdAt: WowFixture.created)
        own.setShared(true)
        #expect(own.scope == .team)
        own.scope = .company
        own.setShared(false)
        own.setShared(true)
        #expect(own.scope == .company)
        own.scope = .team
        own.setShared(false)
        own.setShared(true)
        #expect(own.scope == .team, "Потом выбрали «Команда» — помнится команда")
    }

    @Test("Цель, сохранённая до этой памяти, читается: общая — помнит себя, своя — ничего")
    func sharedKindLegacyDecode() throws {
        let company = #"{"id":"\#(goalID.uuidString)","title":"Выручка","progress":0,"isCompleted":false,"createdAt":800000000,"scope":"company"}"#
        #expect(try JSONDecoder().decode(LineaGoal.self, from: Data(company.utf8)).sharedScope == .company)
        let personal = #"{"id":"\#(goalID.uuidString)","title":"Бег","progress":0,"isCompleted":false,"createdAt":800000000}"#
        #expect(try JSONDecoder().decode(LineaGoal.self, from: Data(personal.utf8)).sharedScope == nil)
    }

    @Test("Миллионы — словом, если так точно: «3,2 млн», но «3 251 000»")
    func compactNumbers() {
        #expect(GoalProgressText.compact(5_000_000) == "5 млн")
        #expect(GoalProgressText.compact(3_200_000) == "3,2 млн")
        #expect(GoalProgressText.compact(3_251_000) == "3\u{00A0}251\u{00A0}000")
        #expect(GoalProgressText.compact(2_500_000_000) == "2,5 млрд")
        #expect(GoalProgressText.compact(18) == "18")
        #expect(GoalProgressText.number(5_000_000) == "5\u{00A0}000\u{00A0}000", "В поле — все цифры")
    }
}
